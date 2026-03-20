{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.services.appData;
  helpers = import ../lib.nix { inherit lib; };

  activeServices = filterAttrs (_: s: s.enable) cfg.services;
in
{
  options.modules.services.appData = {
    enable = mkEnableOption "AppData volume management";

    mount = mkOption {
      type        = types.str;
      default     = "/etc/appData";
      description = "Base path where all appData service volumes are stored.";
    };

    provider = mkOption {
      type        = types.enum [ "plain" "zfs" ];
      default     = "plain";
      description = "Storage backend. 'plain' creates directories only. 'zfs' additionally provisions a ZFS dataset.";
    };

    # ZFS-specific — no defaults; must be set explicitly when provider = "zfs".
    pool = mkOption {
      type        = types.nullOr types.str;
      default     = null;
      description = "ZFS pool name. Required when provider = \"zfs\".";
    };

    dataset = mkOption {
      type        = types.nullOr types.str;
      default     = null;
      description = "ZFS dataset name (relative to pool). Required when provider = \"zfs\".";
    };

    services = mkOption {
      type        = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkOption {
            type    = types.bool;
            default = true;
          };

          appID = mkOption {
            type        = types.str;
            default     = helpers.toCamelCase name;
            description = "Filesystem-safe identifier derived from the service name. Becomes the directory name under mount.";
          };

          owner = mkOption {
            type    = types.str;
            default = "root";
          };

          group = mkOption {
            type    = types.str;
            default = "root";
          };

          mode = mkOption {
            type    = types.str;
            default = "0755";
          };
        };
      }));
      default     = {};
      description = "Service volumes registered by service modules. Each entry creates a subdirectory under mount.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.provider != "zfs" || (cfg.pool != null && cfg.dataset != null);
        message   = "modules.services.appData: pool and dataset must be set when provider = \"zfs\"";
      }
    ];

    systemd.services."appdata-init" = {
      description     = "Initialize appData storage and service directories";
      wantedBy        = [ "multi-user.target" ];
      after           = [ "local-fs.target" ]
        ++ optional (cfg.provider == "zfs") "zfs_load_data.service";
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
      path   = [ pkgs.coreutils ] ++ optional (cfg.provider == "zfs") pkgs.zfs;
      script = ''
        ${optionalString (cfg.provider == "zfs") ''
          zfs create -p -o mountpoint=${cfg.mount} ${cfg.pool}/${cfg.dataset} 2>/dev/null || true
          zfs mount ${cfg.pool}/${cfg.dataset} 2>/dev/null || true
        ''}

        mkdir -p ${escapeShellArg cfg.mount}

        ${concatStringsSep "\n" (mapAttrsToList (_: s: ''
          mkdir -p ${escapeShellArg "${cfg.mount}/${s.appID}"}
          chmod ${s.mode} ${escapeShellArg "${cfg.mount}/${s.appID}"}
          chown ${s.owner}:${s.group} ${escapeShellArg "${cfg.mount}/${s.appID}"}
        '') activeServices)}
      '';
    };

    # All Docker containers wait for appdata-init before starting.
    systemd.services.docker = mkIf (config.virtualisation.docker.enable or false) {
      after = [ "appdata-init.service" ];
      wants = [ "appdata-init.service" ];
    };
  };
}
