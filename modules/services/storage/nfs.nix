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
        /data                   10.150.10.0/23(ro,fsid=0,no_subtree_check,crossmnt) 10.150.100.0/23(ro,fsid=0,no_subtree_check,crossmnt) 10.100.0.0/18(ro,fsid=0,no_subtree_check,crossmnt) 100.64.0.0/10(ro,fsid=0,no_subtree_check,crossmnt)
        /data/docker-appdata    10.150.10.0/23(rw,fsid=1001,no_subtree_check,crossmnt) 10.150.100.0/23(ro,fsid=1001,no_subtree_check,crossmnt) 10.100.0.0/18(rw,fsid=1001,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1001,no_subtree_check,crossmnt)
        /data/media             10.150.10.0/23(rw,fsid=1002,no_subtree_check,crossmnt) 10.150.100.0/23(ro,fsid=1002,no_subtree_check,crossmnt) 10.100.0.0/18(rw,fsid=1002,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1002,no_subtree_check,crossmnt)
        /data/tristonyoder      10.150.10.0/23(rw,fsid=1003,no_subtree_check,crossmnt) 10.150.100.0/23(ro,fsid=1003,no_subtree_check,crossmnt) 10.150.100.10(rw,fsid=1003,no_subtree_check,crossmnt) 10.100.0.0/18(rw,fsid=1003,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1003,no_subtree_check,crossmnt)
        /data/backups           10.150.10.0/23(rw,fsid=1004,no_subtree_check,crossmnt) 10.150.100.0/23(ro,fsid=1004,no_subtree_check,crossmnt) 10.100.0.0/18(rw,fsid=1004,no_subtree_check,crossmnt) 100.64.0.0/10(rw,fsid=1004,no_subtree_check,crossmnt)
        /data/nix-builds        10.150.10.0/23(ro,fsid=1005,no_subtree_check,crossmnt) 10.150.100.0/23(ro,fsid=1005,no_subtree_check,crossmnt) 10.100.0.0/18(ro,fsid=1005,no_subtree_check,crossmnt) 100.64.0.0/10(ro,fsid=1005,no_subtree_check,crossmnt)
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
