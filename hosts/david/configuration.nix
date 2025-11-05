# Configuration for david - Main Server
# Hosts all services including infrastructure, media, productivity, and storage

{ config, pkgs, lib, nixpkgs, nixpkgs-unstable, nix-bitcoin, ... }:
{
  # Import common configuration and server profile
  # Note: Module imports (./modules, ./docker, etc.) are handled by flake.nix
  # The server profile (../../profiles/server.nix) enables all server services
  
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "david";
  networking.domain = "theyoder.family";
  system.stateVersion = "23.11"; # Did you read the comment?
  system.autoUpgrade.channel = "https://nixos.org/channels/nixos-23.11/";

  # =============================================================================
  # HOST-SPECIFIC SETTINGS
  # =============================================================================
  
  # All module enables are set in ../../profiles/server.nix
  # You can override any profile settings here if needed for this specific host
  
  # GroupMe Bridge - Whitelist user for provisioning
  modules.services.communication.mautrix-groupme = {
    provisioningWhitelist = [
      "@triston:theyoder.family"
    ];
  };
  
  # iMessage Bridge - BlueBubbles configuration
  modules.services.communication.mautrix-imessage = {
    blueBubblesUrl = "http://macservices:1234";
    provisioningWhitelist = [
      "@triston:theyoder.family"
    ];
  };
  
  # Stalwart Mail Server
  modules.services.communication.stalwart-mail.enable = false;
  
  # =============================================================================
  # CADDY CONFIGURATION FOR TECHNITIUM DNS
  # =============================================================================
  
  # Technitium DNS Web UI and DoH - dns01.theyoder.family
  services.caddy.virtualHosts."dns01.theyoder.family" = {
    extraConfig = ''
      # Define matchers for allowed IP ranges (internal networks + Tailscale)
      @internal {
        remote_ip 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10
      }
      
      # Handle requests from allowed internal IPs
      handle @internal {
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
      }
      
      # Handle requests from disallowed IPs (external access)
      handle {
        respond "Access Forbidden - Internal Network Only" 403
      }
      
      import cloudflare_tls
    '';
  };

  # =============================================================================
  # ADDITIONAL SERVICES
  # =============================================================================
  
  # NextDNS Dynamic DNS
  systemd.services = {
    nextdns-dyndns = {
      path = [ pkgs.curl ];
      script = "curl $(cat ${config.age.secrets.nextdns-link.path})";
      startAt = "hourly";
    };
  };
}
