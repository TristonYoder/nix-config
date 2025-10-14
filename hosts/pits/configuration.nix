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
  # HARDWARE OVERRIDES
  # =============================================================================
  
  # Disable the boot module - VPS uses legacy BIOS, not EFI
  # Bootloader config is in hardware-configuration.nix (GRUB on /dev/sda)
  modules.hardware.boot.enable = lib.mkForce false;

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
  # Note: cloudflare_tls snippet is defined globally in the Caddy module
  
  # Matrix Synapse - Reverse proxy to david
  # Note: Using automatic HTTPS with HTTP-01 challenge instead of DNS-01
  # because Cloudflare DNS plugin fails with .family TLD zone detection
  services.caddy.virtualHosts."matrix.theyoder.family" = {
    extraConfig = ''
      reverse_proxy /_matrix/* http://david:8448
      reverse_proxy /_synapse/client/* http://david:8448
      # No TLS config - let Caddy use default HTTP-01 challenge
    '';
  };
  
  # Matrix Well-Known Delegation for theyoder.family is handled by Cloudflare Tunnel
  # configured in Cloudflare dashboard to route /.well-known/matrix/* to david
  
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
      PasswordAuthentication = false;  # Secure from day 1 - SSH keys configured in users.nix
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

