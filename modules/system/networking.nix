{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.networking;
in
{
  options.modules.system.networking = {
    enable = mkEnableOption "Basic networking configuration";
    
    firewallPorts = mkOption {
      type = types.listOf types.port;
      default = [ 22 111 2049 3389 4000 4001 4002 20048 8234 ];
      description = "TCP ports to open in firewall";
    };
    
    allowPing = mkOption {
      type = types.bool;
      default = true;
      description = "Allow ICMP ping requests";
    };
  };

  config = mkIf cfg.enable {
    # Enable networking
    networking.networkmanager.enable = true;
    
    # Firewall configuration
    networking.firewall = {
      allowedTCPPorts = cfg.firewallPorts;
      allowPing = cfg.allowPing;
    };
  };
}

