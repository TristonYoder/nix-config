{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.beets;

  beetsConfig = pkgs.writeText "beets-config.yaml" ''
    directory: ${cfg.musicDir}
    library: ${cfg.dataDir}/beets.db

    import:
      move: true
      write: true
      quiet: true
      incremental: true
      incremental_skip_later: true

    plugins: fetchart embedart chroma

    fetchart:
      auto: yes

    embedart:
      auto: yes

    ${cfg.extraConfig}
  '';
in
{
  options.modules.services.media.beets = {
    enable = mkEnableOption "Beets music library organizer";

    musicDir = mkOption {
      type = types.str;
      default =
        if config.modules.services.media.jellyfin.enable
        then "${config.modules.services.media.jellyfin.mediaDir}/Music"
        else "/data/media/Music";
      description = "Organized music library directory";
    };

    inboxDir = mkOption {
      type = types.str;
      default =
        if config.modules.services.media.jellyfin.enable
        then "${config.modules.services.media.jellyfin.mediaDir}/Downloads"
        else "/data/media/Downloads";
      description = "Directory to import new music from";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/beets";
      description = "Directory for beets database and state";
    };

    user = mkOption {
      type = types.str;
      default = "jellyfin";
      description = "User to run beets as";
    };

    group = mkOption {
      type = types.str;
      default = "media";
      description = "Group to run beets as";
    };

    onCalendar = mkOption {
      type = types.str;
      default = "hourly";
      description = "Systemd calendar expression for import schedule";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Additional beets YAML configuration";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.beets-import = {
      description = "Beets music library import";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${pkgs.beets}/bin/beet --config ${beetsConfig} import ${cfg.inboxDir}";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir cfg.musicDir cfg.inboxDir ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictRealtime = true;
        LockPersonality = true;
      };
    };

    systemd.timers.beets-import = {
      description = "Beets music library import timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
      };
    };
  };
}
