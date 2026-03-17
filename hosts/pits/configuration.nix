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
    
  # Example: Enable Syncthing for edge data sync
  # modules.services.storage.syncthing.enable = true;

  # Ensure Technitium DNS is enabled on pits (edge DNS host)
  modules.services.infrastructure.technitium.enable = true;
  
  # =============================================================================
  # CADDY CONFIGURATION FOR TECHNITIUM DNS
  # =============================================================================

  # Technitium DNS Web UI and DoH - dns02.<baseDomain>
  modules.services.vHosts.hosts."dns02.${config.networking.domain}" =
    lib.mkIf config.modules.services.infrastructure.technitium.enable {
      managedProxy = false;  # Use custom routing for multi-backend setup
      public = false;  # Restrict to internal networks (auto-applied by module)
      extraConfig = ''
        # DNS over HTTPS endpoint - Technitium runs DoH on port 5353
        handle /dns-query* {
          reverse_proxy http://localhost:5353 {
            header_up Host {upstream_hostport}
            header_up X-Real-IP {remote_host}
          }
        }

        # Web UI for all other paths
        handle {
          reverse_proxy http://localhost:5380 {
            header_up Host {upstream_hostport}
            header_up X-Real-IP {remote_host}
          }
        }
      '';
    };

  # =============================================================================
  # CADDY CONFIGURATION
  # =============================================================================
  
  # Caddy is enabled by the edge profile
  # Add custom Caddy configuration here or in the Caddy module
  # Note: cloudflare_tls snippet is defined globally in the Caddy module
  
  # Matrix Synapse - Reverse proxy to david
  # Uses Cloudflare DNS-01 challenge for automatic HTTPS
  modules.services.vHosts.hosts."matrix.${config.networking.domain}" = {
    public = true;
    managedProxy = false;
    extraConfig = ''
      reverse_proxy /_matrix/* http://david:8448
      reverse_proxy /_synapse/client/* http://david:8448
    '';
  };
  
  # Pixelfed - Reverse proxy to david's nginx
  # Uses Cloudflare DNS-01 challenge for automatic HTTPS
  modules.services.vHosts.hosts."loveinfocus.photos" = {
    public = true;
    reverseProxyHost = "david";
    reverseProxyPort = 8085;
  };
  
  # Stalwart Mail Webmail Interface - Reverse proxy to david
  # Uses Cloudflare DNS-01 challenge for automatic HTTPS
  modules.services.vHosts.hosts."mail.7andco.dev" = {
    public = true;
    reverseProxyHost = "david";
    reverseProxyPort = 8080;
    serverAliases = [
      # MTA-STS for mail security policy
      "mta-sts.7andco.dev"
      # Autoconfig for mail clients
      "autoconfig.7andco.dev"
      "autodiscover.7andco.dev"
    ];
  };
  
  # Stalwart Mail Admin Interface - Reverse proxy to david
  # Uses Cloudflare DNS-01 challenge for automatic HTTPS
  modules.services.vHosts.hosts."admin.mail.7andco.dev" = {
    public = true;
    reverseProxyHost = "david";
    reverseProxyPort = 8081;
  };
  
  # Postal Mail Server Web UI - Local service on PITS
  # Uses Cloudflare DNS-01 challenge for automatic HTTPS
  modules.services.vHosts.hosts."postal.7andco.dev" = {
    public = true;
    reverseProxyPort = 5000;
    serverAliases = [
      "postal.mail.7andco.dev"
    ];
  };
  
  # Nextcloud - Reverse proxy to david
  # Uses Cloudflare DNS-01 challenge for automatic HTTPS
  # PITS terminates SSL for external access, forwards to David over Tailscale
  modules.services.vHosts.hosts."cloud.7andco.dev" = {
    public = true;
    managedProxy = false;
    extraConfig = ''
      reverse_proxy https://david {
        transport http {
          tls_insecure_skip_verify
        }
      }
    '';
  };
  
  # Well-Known Delegation for Federation is handled by the wellknown module
  # (modules/services/communication/wellknown.nix)
  # It automatically configures routing based on hostname:
  #   - david: proxies to localhost
  #   - PITS: proxies to david via Tailscale
  
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
  #   flake = "github:yourusername/nix-config#pits";
  # };
  
  # =============================================================================
  # MONITORING & ALERTS (Optional)
  # =============================================================================
  
  # Consider adding monitoring for a public-facing server
  # Example: Prometheus node exporter, Grafana agent, etc.
}
