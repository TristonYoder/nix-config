{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.kiwix;
  libraryFile = "${cfg.zimDir}/library.xml";

  # "wikipedia_en_all_maxi" -> wikipedia/wikipedia_en_all_maxi
  # "stack_exchange/superuser.com_en_all" is passed through as-is, for books whose
  # download directory isn't the first underscore-separated part of the name.
  bookPath = book:
    if hasInfix "/" book then book
    else "${head (splitString "_" book)}/${book}";

  syncScript = pkgs.writeShellApplication {
    name = "kiwix-sync";
    runtimeInputs = with pkgs; [ coreutils curl gnugrep gnused cfg.package ];
    text = ''
      mirror=${escapeShellArg cfg.mirror}
      cd ${escapeShellArg cfg.zimDir}

      books=(${escapeShellArgs (map bookPath cfg.books)})

      for book in "''${books[@]}"; do
        dir=''${book%/*}
        name=''${book##*/}

        # Pick the newest dated build from the directory listing
        latest=$(curl -fsSL "$mirror/$dir/" \
          | grep -oE "\"''${name}_[0-9]{4}-[0-9]{2}\.zim\"" \
          | tr -d '"' | sort -u | tail -n1) || true
        if [ -z "$latest" ]; then
          echo "kiwix-sync: no build found for $book" >&2
          continue
        fi

        if [ ! -f "$latest" ]; then
          echo "kiwix-sync: downloading $latest"
          # A failed book is skipped, not fatal, so the library still gets rebuilt
          # for the others. The .part file is kept and resumed on the next run.
          if ! curl -fL --retry 5 -C - -o "$latest.part" "$mirror/$dir/$latest"; then
            echo "kiwix-sync: download of $latest failed, will resume next run" >&2
            continue
          fi
          expected=$(curl -fsSL "$mirror/$dir/$latest.sha256" | cut -d' ' -f1) || true
          if [ -z "$expected" ]; then
            echo "kiwix-sync: no checksum for $latest, leaving it unverified as .part" >&2
            continue
          fi
          actual=$(sha256sum "$latest.part" | cut -d' ' -f1)
          if [ "$expected" != "$actual" ]; then
            echo "kiwix-sync: checksum mismatch for $latest, discarding" >&2
            rm -f "$latest.part"
            continue
          fi
          mv "$latest.part" "$latest"
        fi

        # Drop superseded builds of this book only after the new one verified
        for old in "''${name}"_[0-9][0-9][0-9][0-9]-[0-9][0-9].zim; do
          if [ -f "$old" ] && [ "$old" != "$latest" ]; then rm -v "$old"; fi
        done
      done

      # Rebuild the library from whatever is on disk, including hand-placed ZIMs.
      # kiwix-serve runs with --monitorLibrary and picks up the swap without a restart.
      rm -f library.xml.new
      echo '<library version="20110515"></library>' > library.xml.new
      for zim in *.zim; do
        if [ -f "$zim" ]; then kiwix-manage library.xml.new add "$PWD/$zim"; fi
      done
      chmod 0644 library.xml.new
      mv library.xml.new library.xml
    '';
  };
in
{
  options.modules.services.productivity.kiwix = {
    enable = mkEnableOption "Kiwix offline Wikipedia/ZIM server";

    domain = mkOption {
      type = types.str;
      default = "kiwix.${config.networking.domain}";
      description = "Domain for Kiwix";
    };

    port = mkOption {
      type = types.port;
      default = 8383;
      description = "kiwix-serve HTTP port";
    };

    package = mkPackageOption pkgs "kiwix-tools" { };

    zimDir = mkOption {
      type = types.str;
      default = "/data/kiwix";
      description = ''
        Directory holding ZIM files and the generated library.xml. Any ZIM
        dropped here by hand is served too, after the next sync run.
      '';
    };

    books = mkOption {
      type = types.listOf types.str;
      default = [ "wikipedia_en_all_maxi" ];
      example = [ "wikipedia_en_all_nopic" "wiktionary_en_all_maxi" "stack_exchange/superuser.com_en_all" ];
      description = ''
        ZIM books to keep downloaded and up to date, by name without the date
        suffix (see https://download.kiwix.org/zim/). The download directory is
        taken from the first part of the name; prefix it as `dir/name` when it differs.
        Updates download the new build before deleting the old one, so allow
        free space for two copies of the largest book.
      '';
    };

    mirror = mkOption {
      type = types.str;
      default = "https://download.kiwix.org/zim";
      description = "Base URL of the Kiwix ZIM mirror.";
    };

    updateInterval = mkOption {
      type = types.str;
      default = "monthly";
      description = "systemd OnCalendar expression for checking for new ZIM builds.";
    };
  };

  config = mkIf cfg.enable {
    services.kiwix-serve = {
      enable = true;
      package = cfg.package;
      address = "127.0.0.1";
      port = cfg.port;
      libraryPath = libraryFile;
      extraArgs = [ "--monitorLibrary" ];
    };

    # Same BindReadOnlyPaths-style race as navidrome: don't start against an
    # unmounted /data and serve an empty library.
    systemd.services.kiwix-serve = {
      unitConfig.RequiresMountsFor = [ cfg.zimDir ];
      requires = [ "kiwix-init.service" ];
      after = [ "kiwix-init.service" ];
    };

    users.users.kiwix = {
      isSystemUser = true;
      group = "kiwix";
    };
    users.groups.kiwix = { };

    # kiwix-serve runs as a DynamicUser, so ZIMs must be world-readable.
    # The empty library lets kiwix-serve start before the first sync finishes.
    # Not tmpfiles: it refuses to create a kiwix-owned path under a parent owned
    # by another non-root user ("unsafe path transition"), e.g. /data/media.
    systemd.services.kiwix-init = {
      description = "Prepare the Kiwix ZIM directory";
      unitConfig.RequiresMountsFor = [ cfg.zimDir ];
      script = ''
        install -d -m 0755 -o kiwix -g kiwix ${escapeShellArg cfg.zimDir}
        if [ ! -s ${escapeShellArg libraryFile} ]; then
          echo '<library version="20110515"></library>' > ${escapeShellArg libraryFile}
          chown kiwix:kiwix ${escapeShellArg libraryFile}
          chmod 0644 ${escapeShellArg libraryFile}
        fi
      '';
      # Gate for kiwix-serve: retries a failing script (e.g. the dataset not yet
      # writable). A failed mount dependency never runs the unit, so Restart= can't
      # cover that; like navidrome, restart kiwix-serve once the mount is back.
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Timer-driven, so no Restart=: the next run retries, and a restart mid-download
    # would race the timer. curl -C resumes a partial download either way.
    systemd.services.kiwix-sync = {
      description = "Download and update Kiwix ZIM files";
      wants = [ "network-online.target" ];
      requires = [ "kiwix-init.service" ];
      after = [ "network-online.target" "kiwix-init.service" ];
      unitConfig.RequiresMountsFor = [ cfg.zimDir ];
      # A deploy must not kill a multi-hour download; changes apply on the next run.
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        User = "kiwix";
        Group = "kiwix";
        UMask = "0022";
        ExecStart = getExe syncScript;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };

    systemd.timers.kiwix-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.updateInterval;
        Persistent = true;
        RandomizedDelaySec = "6h";
      };
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Kiwix";
      category = "productivity";
      icon = "kiwix";
    };
  };
}
