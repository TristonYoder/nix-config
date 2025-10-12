{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.sunshine;
in
{
  options.modules.services.media.sunshine = {
    enable = mkEnableOption "Sunshine game streaming server";
    
    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Start Sunshine automatically on boot";
    };
    
    capSysAdmin = mkOption {
      type = types.bool;
      default = true;
      description = "Grant CAP_SYS_ADMIN capability";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Sunshine";
    };
  };

  config = mkIf cfg.enable {
    # Sunshine game streaming
    services.sunshine = {
      enable = true;
      autoStart = cfg.autoStart;
      capSysAdmin = cfg.capSysAdmin;
      openFirewall = cfg.openFirewall;
    };

    # Steam gaming platform (typically used with Sunshine)
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      localNetworkGameTransfers.openFirewall = true;
    };
  };
}

