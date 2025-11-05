{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.technitium;
in
{
  options.modules.services.infrastructure.technitium = {
    enable = mkEnableOption "Technitium DNS Server";
    
    package = mkOption {
      type = types.package;
      default = pkgs.technitium-dns-server;
      description = "Technitium DNS Server package to use";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for DNS server";
    };
    
    firewallUDPPorts = mkOption {
      type = types.listOf types.port;
      default = [ 53 ];
      description = "UDP ports to open in firewall for DNS server";
    };
    
    firewallTCPPorts = mkOption {
      type = types.listOf types.port;
      default = [ 53 5353 5380 53443 ];
      description = "TCP ports to open in firewall for DNS server (53=DNS, 5353=DoH, 5380=Web UI, 53443=HTTPS Web UI)";
    };
    
    # Shared configuration options for consistent settings across hosts
    sharedConfig = mkOption {
      type = types.bool;
      default = true;
      description = "Use shared configuration settings for consistency across hosts";
    };
  };

  config = mkIf cfg.enable {
    # Apply shared configuration by default
    modules.services.infrastructure.technitium = mkIf cfg.sharedConfig {
      package = pkgs.technitium-dns-server;
      openFirewall = true;
      firewallUDPPorts = [ 53 ];
      firewallTCPPorts = [ 53 5353 5380 53443 ];
    };
    
    services.technitium-dns-server = {
      enable = true;
      package = cfg.package;
      openFirewall = cfg.openFirewall;
      firewallUDPPorts = cfg.firewallUDPPorts;
      firewallTCPPorts = cfg.firewallTCPPorts;
    };
  };
}

