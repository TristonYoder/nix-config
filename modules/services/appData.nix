{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.services.appData;
  helpers = import ../lib.nix { inherit lib; };

  activeServices = filterAttrs (_: s: s.enable) cfg.services;

  # Build the encryption flag for a per-service zfs create call.
  # null  = inherit from parent dataset (no flag)
  # "off" = explicitly disable
  # "on"  = explicitly enable (aes-256-gcm; requires key management)
  encFlag = s:
    if      s.encryption == null  then ""
    else if s.encryption == "off" then "-o encryption=off"
    else                               "-o encryption=aes-256-gcm";
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
      description = "Storage backend. 'plain' creates directories only. 'zfs' provisions a ZFS dataset per service.";
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
      description = "ZFS parent dataset (relative to pool). Required when provider = \"zfs\". Each service gets a child dataset under this.";
    };

    disableEncryption = mkOption {
      type        = types.bool;
      default     = false;
      description = "Create the parent ZFS dataset with encryption=off. Set true when the pool is encrypted but appData should not inherit it.";
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
            description = "Filesystem-safe identifier. Becomes the ZFS child dataset name and directory name under mount.";
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

          encryption = mkOption {
            type        = types.nullOr (types.enum [ "off" "on" ]);
            default     = null;
            description = ''
              Per-service ZFS dataset encryption override. Only applies when provider = "zfs".
              null = inherit from parent dataset (default: off when disableEncryption = true on server).
              "off" = explicitly disable encryption.
              "on"  = explicitly enable encryption (aes-256-gcm; requires manual key management).
            '';
          };
        };
      }));
      default     = {};
      description = "Service volumes registered by service modules. Each entry creates a ZFS child dataset (zfs) or subdirectory (plain) under mount.";
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
      description     = "Initialize appData storage and per-service ZFS datasets / directories";
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
          # Ensure parent dataset exists and is mounted
          zfs create -p ${optionalString cfg.disableEncryption "-o encryption=off"} -o mountpoint=${cfg.mount} ${cfg.pool}/${cfg.dataset} 2>/dev/null || true
          zfs mount ${cfg.pool}/${cfg.dataset} 2>/dev/null || true
        ''}

        mkdir -p ${escapeShellArg cfg.mount}

        ${concatStringsSep "\n" (mapAttrsToList (_: s:
          let
            mountPath   = "${cfg.mount}/${s.appID}";
            datasetPath = "${cfg.pool}/${cfg.dataset}/${s.appID}";
          in
          (optionalString (cfg.provider == "zfs") ''
            # ${s.appID}: create child dataset if it doesn't exist
            zfs create -p ${encFlag s} -o mountpoint=${mountPath} ${datasetPath} 2>/dev/null || true
            zfs mount ${datasetPath} 2>/dev/null || true
          '') +
          (optionalString (cfg.provider != "zfs") ''
            mkdir -p ${escapeShellArg mountPath}
          '') + ''
            chmod ${s.mode} ${escapeShellArg mountPath}
            chown ${s.owner}:${s.group} ${escapeShellArg mountPath}
          ''
        ) activeServices)}
      '';
    };

    # All Docker containers wait for appdata-init before starting.
    systemd.services.docker = mkIf (config.virtualisation.docker.enable or false) {
      after = [ "appdata-init.service" ];
      wants = [ "appdata-init.service" ];
    };
  };
}
