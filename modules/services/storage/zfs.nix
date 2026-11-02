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
    # Ordered like nixpkgs' zfs-import-<pool> units: before zfs-import.target,
    # and so before zfs-mount and local-fs.target. Without this the import
    # (~40s) raced every service with state under /data, and postgresql and
    # syncthing failed at boot on paths that did not exist yet.
    systemd.services."zfs_load_data" = mkIf (cfg.autoImportPool != null) {
      path = [ pkgs.zfs ];
      unitConfig.DefaultDependencies = false;
      wants = [ "systemd-udev-settle.service" ];
      after = [ "systemd-udev-settle.service" "systemd-modules-load.service" ];
      before = [ "zfs-import.target" "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      requiredBy = [ "zfs-import.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        zpool import ${cfg.autoImportPool} -f || true
      '';
    };
  };
}

