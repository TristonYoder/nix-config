# One-way publish of an Obsidian vault into Outline. The vault is the source
# of truth; Outline is a read-only copy and nothing here writes to the vault.
#
#   outline-vault-sync-watch  long-running inotifywait on the vault; starts the
#                             sync after debounceSeconds of quiet (or
#                             maxWaitSeconds of constant editing)
#   outline-vault-sync        oneshot sync; overlapping starts merge into one run
#   outline-vault-sync-full   nightly reconcile that also verifies every mapped
#                             document still exists in Outline
#
# See README.md in this folder for deployment and troubleshooting.
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.outlineVaultSync;
  user = "outline-vault-sync";
  stateDir = "/var/lib/outline-vault-sync";

  syncBin = pkgs.writers.writePython3Bin "outline-vault-sync" {
    libraries = [ pkgs.python3Packages.requests ];
    flakeIgnore = [ "E501" "W503" "W504" ];
  } (builtins.readFile ./sync.py);

  configFile = pkgs.writeText "outline-vault-sync.json" (builtins.toJSON {
    vault = cfg.vaultPath;
    inherit (cfg) outlineUrl excludes collectionNames rootCollection
      protectedCollections collectionPermission maxArchivePerRun;
    inherit stateDir;
  });

  sync = "${syncBin}/bin/outline-vault-sync --config ${configFile}";
  syncUnit = "outline-vault-sync.service";

  # The watcher needs read on every directory and the sync on every note.
  # Syncthing reapplies mode bits from the sending device, and chmod on a file
  # that has an ACL rewrites its mask, so the grant is reapplied before every
  # run instead of once. The watcher ignores attribute changes, so this cannot
  # retrigger a sync.
  grantRead = pkgs.writeShellScript "outline-vault-sync-grant-read" ''
    set -eu
    ${pkgs.acl}/bin/setfacl -R -m u:${user}:rX ${escapeShellArg cfg.vaultPath}
    ${pkgs.findutils}/bin/find ${escapeShellArg cfg.vaultPath} -type d \
      -exec ${pkgs.acl}/bin/setfacl -d -m u:${user}:rX {} +
  '';

  watch = pkgs.writeShellScript "outline-vault-sync-watch" ''
    set -uo pipefail
    debounce=${toString cfg.debounceSeconds}
    maxwait=${toString cfg.maxWaitSeconds}
    exclude=$(${sync} --print-watch-exclude)

    trigger() {
      # A start request while the sync is running would merge into that run
      # and miss changes it already read past, so wait for it to finish
      while [ "$(systemctl show -P ActiveState ${syncUnit})" = activating ]; do
        sleep 5
      done
      echo "starting sync"
      systemctl start ${syncUnit} || echo "sync failed; see journalctl -u ${syncUnit}"
    }

    # Sync once at startup to pick up anything changed while not watching
    now=$(date +%s)
    pending=1 first=$now last=$now
    while :; do
      if [ "$pending" = 1 ]; then
        now=$(date +%s)
        wait=$(( last + debounce - now ))
        cap=$(( first + maxwait - now ))
        [ "$cap" -lt "$wait" ] && wait=$cap
        if [ "$wait" -le 0 ]; then
          pending=0
          trigger
          continue
        fi
        read -r -t "$wait" event
        rc=$?
        [ "$rc" -gt 128 ] && continue
      else
        read -r event
        rc=$?
      fi
      if [ "$rc" -ne 0 ]; then
        echo "inotifywait exited" >&2
        exit 1
      fi
      now=$(date +%s)
      if [ "$pending" = 0 ]; then
        echo "change detected: $event"
        first=$now
      fi
      pending=1 last=$now
    done < <(${pkgs.inotify-tools}/bin/inotifywait -m -r -q --format '%e %w%f' \
      -e close_write,moved_to,moved_from,create,delete,delete_self,move_self \
      --exclude "$exclude" ${escapeShellArg cfg.vaultPath})
  '';

  # Only the vault is visible: /home is an empty tmpfs, and a vault outside
  # /home gets its top-level directory (e.g. /data) hidden the same way
  vaultTop = head (filter (s: s != "") (splitString "/" cfg.vaultPath));
  hideRoot = optional (!elem vaultTop [ "home" "root" "run" "var" "nix" "etc" "usr" "tmp" ])
    "/${vaultTop}:ro";

  sandbox = {
    User = user;
    Group = user;
    UMask = "0077";
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = "tmpfs";
    TemporaryFileSystem = hideRoot;
    # Quoted: systemd splits this list on whitespace
    BindReadOnlyPaths = [ "\"${cfg.vaultPath}\"" ];
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" "~@privileged" ];
    CapabilityBoundingSet = "";
  };

  syncService = args: {
    description = "Publish Obsidian vault to Outline${optionalString (args != "") " (full reconcile)"}";
    after = [ "network-online.target" "outline.service" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ cfg.vaultPath ];
    serviceConfig = sandbox // {
      Type = "oneshot";
      ExecStartPre = "+${grantRead}";
      ExecStart = "${sync} ${args}";
      # Read from $CREDENTIALS_DIRECTORY at runtime; never in the environment
      LoadCredential = "token:${cfg.tokenFile}";
      StateDirectory = "outline-vault-sync";
      StateDirectoryMode = "0700";
      TimeoutStartSec = "2h";
    };
  };
in
{
  options.modules.services.productivity.outlineVaultSync = {
    enable = mkEnableOption "one-way Obsidian vault to Outline sync";

    active = mkOption {
      type = types.bool;
      readOnly = true;
      internal = true;
      default = cfg.enable && config.modules.services.productivity.outline.enable;
      description = ''
        Whether the sync actually runs. It only does while Outline is enabled
        on this host, so disabling Outline takes this (and its secret) with it.
      '';
    };

    vaultPath = mkOption {
      type = types.str;
      description = ''
        Absolute path to the vault. Use the real path, not one reached through
        a symlink: it is bind-mounted read-only into the sandbox.
      '';
    };

    outlineUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:${toString config.modules.services.productivity.outline.port}";
      description = "Outline base URL";
    };

    tokenFile = mkOption {
      type = types.str;
      default = config.age.secrets.outline-vault-sync-token.path;
      description = "File containing an Outline API key. Passed to the service with LoadCredential.";
    };

    debounceSeconds = mkOption {
      type = types.ints.positive;
      default = 60;
      description = "Sync once the vault has been quiet for this long.";
    };

    maxWaitSeconds = mkOption {
      type = types.ints.positive;
      default = 600;
      description = "Sync at least this often while changes keep arriving.";
    };

    fullSyncSchedule = mkOption {
      type = types.str;
      default = "*-*-* 03:30:00";
      description = "OnCalendar for the full reconcile.";
    };

    excludes = mkOption {
      type = types.listOf types.str;
      default = [ ".obsidian/" ".trash/" "AIOS/history/" ];
      description = ''
        Vault-relative globs never published. `*` stays within one path
        segment, `**` crosses segments, and a match covers everything below
        it. A pattern without `/` matches at any depth. Hidden files,
        Syncthing artifacts and editor swap files are always ignored.
      '';
    };

    collectionNames = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { "theyoder.family" = "Family"; };
      description = "Collection name overrides, keyed by top-level vault folder.";
    };

    rootCollection = mkOption {
      type = types.str;
      default = baseNameOf cfg.vaultPath;
      description = "Collection for notes at the vault root, which have no top-level folder.";
    };

    protectedCollections = mkOption {
      type = types.listOf types.str;
      default = [ "Welcome" ];
      description = "Collections the sync must never write to. A vault folder mapping to one is an error.";
    };

    collectionPermission = mkOption {
      type = types.nullOr (types.enum [ "read" "read_write" ]);
      default = null;
      description = ''
        Workspace-wide permission on collections the sync creates. null keeps
        them private to the API key's user. Only applied at creation.
      '';
    };

    maxArchivePerRun = mkOption {
      type = types.ints.unsigned;
      default = 20;
      description = ''
        A run that would archive more documents than this archives none and
        fails. Touch allow-mass-archive in the state directory to let the next
        run through.
      '';
    };
  };

  config = mkIf cfg.active {
    users.users.${user} = {
      isSystemUser = true;
      group = user;
    };
    users.groups.${user} = { };

    systemd.services.outline-vault-sync = syncService "";
    systemd.services.outline-vault-sync-full = syncService "--full";

    systemd.timers.outline-vault-sync-full = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.fullSyncSchedule;
        Persistent = true;
        RandomizedDelaySec = "15m";
      };
    };

    systemd.services.outline-vault-sync-watch = {
      description = "Watch Obsidian vault and trigger Outline sync";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = [ cfg.vaultPath ];
      path = [ config.systemd.package pkgs.coreutils ];
      serviceConfig = sandbox // {
        ExecStartPre = "+${grantRead}";
        ExecStart = watch;
        Restart = "always";
        RestartSec = 30;
      };
    };

    # Lets the unprivileged watcher start the sync unit, and nothing else
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "${syncUnit}" &&
            action.lookup("verb") == "start" &&
            subject.user == "${user}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
