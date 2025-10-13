{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.samba;
in
{
  options.modules.services.storage.samba = {
    enable = mkEnableOption "Samba/CIFS file sharing";
    
    enableWsdd = mkOption {
      type = types.bool;
      default = true;
      description = "Enable WS-Discovery for Windows 10+ network discovery";
    };
    
    shares = mkOption {
      type = types.attrsOf (types.attrsOf types.unspecified);
      default = {
        "data" = {
          path = "/data";
          writable = true;
          browseable = true;
          guestOk = false;
          validUsers = "tristonyoder";
        };
        "media" = {
          path = "/data/media";
          writable = false;
          browseable = true;
          guestOk = true;
        };
        "tristonyoder" = {
          path = "/data/tristonyoder";
          writable = true;
          browseable = true;
          guestOk = false;
          validUsers = "tristonyoder";
        };
        "carolineyoder" = {
          path = "/data/carolineyoder";
          writable = true;
          browseable = true;
          guestOk = false;
          validUsers = "carolineyoder tristonyoder";
        };
        "backups" = {
          path = "/data/backups";
          writable = true;
          browseable = true;
          guestOk = false;
          validUsers = "carolineyoder tristonyoder";
        };
      };
      description = "Samba share configuration";
    };
  };

  config = mkIf cfg.enable {
    # SMB/CIFS Server Configuration
    services.samba-wsdd = mkIf cfg.enableWsdd {
      enable = true;
      openFirewall = true;
    };
    
    services.samba = {
      enable = true;
      settings = cfg.shares;
    };
  };
}

