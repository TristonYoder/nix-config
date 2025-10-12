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
    systemd.services."zfs_load_data" = mkIf (cfg.autoImportPool != null) {
      path = [ pkgs.zfs ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        zpool import ${cfg.autoImportPool} -f || true 
      '';
      wantedBy = [ "docker-compose-media-aq-root.target" "docker.target" ];
    };
  };
}

