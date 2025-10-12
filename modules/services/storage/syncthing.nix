{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.syncthing;
in
{
  options.modules.services.storage.syncthing = {
    enable = mkEnableOption "Syncthing file synchronization";
    
    user = mkOption {
      type = types.str;
      default = "tristonyoder";
      description = "User to run Syncthing as";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/data/";
      description = "Default folder for new synced folders";
    };
    
    configDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/syncthing";
      description = "Folder for Syncthing's settings and keys";
    };
    
    guiAddress = mkOption {
      type = types.str;
      default = "0.0.0.0:8384";
      description = "GUI listen address";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Syncthing";
    };
  };

  config = mkIf cfg.enable {
    # Syncthing service
    services.syncthing = {
      enable = true;
      user = cfg.user;
      dataDir = cfg.dataDir;
      configDir = cfg.configDir;
      guiAddress = cfg.guiAddress;
    };

    # Firewall configuration
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ 8384 22000 ];
      allowedUDPPorts = [ 22000 21027 ];
    };
  };
}

