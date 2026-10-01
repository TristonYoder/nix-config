{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.zfs;
in
{
  options.modules.services.storage.zfs = {
    enable = mkEnableOption "ZFS filesystem support and management";
    
    hostId = mkOption {
      type = types.str;
      default = "aad77407";
      description = "ZFS host ID (must be unique)";
    };
    
    enableAutoSnapshot = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic ZFS snapshots";
    };
    
    enableAutoScrub = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic ZFS scrubbing";
    };
    
    requestEncryptionCredentials = mkOption {
      type = types.bool;
      default = true;
      description = "Request encryption credentials at boot";
    };
    
    autoImportPool = mkOption {
      type = types.nullOr types.str;
      default = "data";
      description = "Pool name to auto-import at boot (null to disable)";
    };
  };

  config = mkIf cfg.enable {
    # ZFS Configuration
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.requestEncryptionCredentials = cfg.requestEncryptionCredentials;
    networking.hostId = cfg.hostId;
    
    services.zfs.autoSnapshot.enable = cfg.enableAutoSnapshot;
    services.zfs.autoScrub.enable = cfg.enableAutoScrub;

    # ZFS Load Data (Loads unencrypted datasets on encrypted root)
    #
    # This pool isn't covered by NixOS's built-in zfs-import-<pool>.service machinery
    # (it's not listed as a root/extra pool), so nothing orders native services or
    # Docker against it by default. `RequiresMountsFor` on consumers like postgresql
    # only binds to a mount that already exists in /proc/self/mountinfo — it doesn't
    # make the mount happen, so a service starting before this unit races the import
    # and fails outright instead of waiting. Gating `local-fs.target` (the same
    # mechanism the stock zfs-mount.service uses for the root pool) makes every
    # default-dependency unit — postgresql, mariadb, qdrant, docker.service, and
    # therefore every docker-compose-*-root.target — transitively wait for this pool
    # to be imported and mounted before they start.
    systemd.services."zfs_load_data" = mkIf (cfg.autoImportPool != null) {
      path = [ pkgs.zfs ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        zpool import ${cfg.autoImportPool} -f || true
        zfs mount -a || true
      '';
      after = [ "systemd-udev-settle.service" ];
      before = [ "local-fs.target" ];
      wantedBy = [ "local-fs.target" "docker-compose-media-aq-root.target" "docker.target" ];
    };
  };
}

