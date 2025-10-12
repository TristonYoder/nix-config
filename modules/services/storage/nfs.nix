{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.nfs;
in
{
  options.modules.services.storage.nfs = {
    enable = mkEnableOption "NFS server";
    
    lockdPort = mkOption {
      type = types.port;
      default = 4001;
      description = "NFS lockd port";
    };
    
    mountdPort = mkOption {
      type = types.port;
      default = 4002;
      description = "NFS mountd port";
    };
    
    statdPort = mkOption {
      type = types.port;
      default = 4000;
      description = "NFS statd port";
    };
    
    exports = mkOption {
      type = types.lines;
      default = ''
        /data/docker-appdata    10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/media             10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/tristonyoder      10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
        /data/backups           10.150.0.0/16(rw,fsid=1000,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1000,no_subtree_check,crossmnt)
      '';
      description = "NFS exports configuration";
    };
  };

  config = mkIf cfg.enable {
    # NFS Server Configuration
    services.nfs.server = {
      enable = true;
      lockdPort = cfg.lockdPort;
      mountdPort = cfg.mountdPort;
      statdPort = cfg.statdPort;
      extraNfsdConfig = '''';
      exports = cfg.exports;
    };
  };
}

