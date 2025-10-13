# Configuration for pits - Pi in the Sky
# Edge server with public IP serving as entry point for services
# Lightweight NixOS configuration optimized for cloud VPS (AWS, GCloud, Vultr, etc.)

{ config, pkgs, lib, ... }:
{
  # Import edge profile
  # Note: The edge profile (../../profiles/edge.nix) enables Caddy and Tailscale
  # Additional modules are handled by flake.nix
  
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "pits";
  networking.domain = lib.mkDefault "theyoder.family";
  system.stateVersion = "25.05";

  # =============================================================================
  # NETWORK CONFIGURATION
  # =============================================================================
  
  # Public-facing edge server configuration
  # This Pi will have a public IP and handle incoming connections
  
  # Example: Static IP configuration (uncomment and adjust as needed)
  # networking.interfaces.eth0.ipv4.addresses = [{
  #   address = "YOUR_PUBLIC_IP";
  #   prefixLength = 24;
  # }];
  # networking.defaultGateway = "YOUR_GATEWAY";
  # networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
  
  # Or use DHCP (default)
  networking.useDHCP = lib.mkDefault true;
  
  # Open ports for Caddy (HTTP/HTTPS)
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      80    # HTTP
      443   # HTTPS
      22    # SSH (consider changing to non-standard port)
    ];
    # allowedUDPPorts = [ ];
  };

  # =============================================================================
  # EDGE-SPECIFIC SERVICES
  # =============================================================================
  
  # All module enables are set in ../../profiles/edge.nix
  # You can override or add specific services here
  
  # Example: Enable Cloudflare tunnel if using Cloudflare
  # modules.services.infrastructure.cloudflared.enable = true;
  
  # Example: Enable Syncthing for edge data sync
  # modules.services.storage.syncthing.enable = true;
  
  # =============================================================================
  # CADDY CONFIGURATION
  # =============================================================================
  
  # Caddy is enabled by the edge profile
  # Add custom Caddy configuration here or in the Caddy module
  
  # Example: Custom Caddy virtual hosts for edge services
  # services.caddy.virtualHosts."example.theyoder.family" = {
  #   extraConfig = ''
  #     reverse_proxy http://internal-server:port
  #   '';
  # };
  
  # =============================================================================
  # TAILSCALE CONFIGURATION
  # =============================================================================
  
  # Tailscale is enabled by the edge profile
  # It will connect this edge server back to your Tailscale network
  # allowing secure communication with internal services
  
  # Tailscale will auto-authenticate using the auth key in secrets
  # Make sure to set up the Tailscale auth key secret for this host
  
  # =============================================================================
  # SYSTEM OPTIMIZATION FOR RASPBERRY PI / EDGE DEVICES
  # =============================================================================
  
  # Reduce memory usage
  services.journald.extraConfig = ''
    SystemMaxUse=50M
    RuntimeMaxUse=25M
  '';
  
  # Optimize swap for limited RAM (if using swap)
  # zramSwap.enable = true;
  # zramSwap.memoryPercent = 50;
  
  # =============================================================================
  # ADDITIONAL PACKAGES FOR EDGE SERVER
  # =============================================================================
  
  environment.systemPackages = with pkgs; [
    # Network tools
    nmap
    iperf
    tcpdump
    
    # Monitoring
    htop
    iotop
    
    # Utilities
    tmux
    vim
  ];
  
  # =============================================================================
  # SSH HARDENING (Important for public-facing server)
  # =============================================================================
  
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      # For initial setup, password authentication is enabled (from core.nix)
      # After SSH keys are configured, uncomment below to disable password auth:
      # PasswordAuthentication = lib.mkForce false;
      KbdInteractiveAuthentication = false;
    };
    # Consider changing to non-standard port
    # ports = [ 2222 ];
  };
  
  # =============================================================================
  # AUTOMATIC UPDATES (Recommended for edge security)
  # =============================================================================
  
  # Uncomment to enable automatic security updates
  # system.autoUpgrade = {
  #   enable = true;
  #   allowReboot = false;  # Set to true if you want automatic reboots
  #   dates = "daily";
  #   flake = "github:yourusername/david-nixos#pits";
  # };
  
  # =============================================================================
  # MONITORING & ALERTS (Optional)
  # =============================================================================
  
  # Consider adding monitoring for a public-facing server
  # Example: Prometheus node exporter, Grafana agent, etc.
}

