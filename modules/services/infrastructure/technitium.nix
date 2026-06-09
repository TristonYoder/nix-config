{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.technitium;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  options.modules.services.infrastructure.technitium = {
    enable = mkEnableOption "Technitium DNS Server";
    
    package = mkOption {
      type = types.package;
      default = pkgs-unstable.technitium-dns-server;
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
      package = pkgs-unstable.technitium-dns-server;
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

    # Work around BindPaths conflict with DynamicUser + StateDirectory on systemd 257.
    # The auto-generated BindPaths override breaks directory permissions for the
    # dynamic user, causing "Access to the path 'blocklists' is denied" on startup.
    systemd.services.technitium-dns-server.serviceConfig = {
      BindPaths = lib.mkForce "";
      WorkingDirectory = lib.mkForce "";
    };

    # Prune Technitium logs (>7 days) and stats (>30 days) daily.
    # Without retention these grow to gigabytes — observed 9GB of logs on pits.
    systemd.services.technitium-prune = {
      description = "Prune old Technitium DNS logs and stats";
      serviceConfig.Type = "oneshot";
      script = ''
        find /var/lib/private/technitium-dns-server/logs -name '*.log' -mtime +7 -delete || true
        find /var/lib/private/technitium-dns-server/stats -name '*.stat' -mtime +30 -delete || true
      '';
    };

    systemd.timers.technitium-prune = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}

