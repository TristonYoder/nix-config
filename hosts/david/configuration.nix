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
  
  # =============================================================================
  # ADDITIONAL SERVICES
  # =============================================================================
  
  # NextDNS Dynamic DNS
  systemd.services = {
    nextdns-dyndns = {
      path = [ pkgs.curl ];
      script = "curl https://link-ip.nextdns.io/{a_secret_was_here}/{a_secret_was_here}";
      startAt = "hourly";
    };
  };
  
  # =============================================================================
  # CADDY CONFIGURATION - LAN/Internal Access
  # =============================================================================
  
  # Matrix Well-Known Delegation - Serve on main domain for internal LAN access
  services.caddy.virtualHosts."theyoder.family" = {
    extraConfig = ''
      handle /.well-known/matrix/server {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond `{"m.server": "matrix.theyoder.family:443"}` 200
      }
      handle /.well-known/matrix/client {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond `{"m.homeserver":{"base_url":"https://matrix.theyoder.family"}}` 200
      }
      # Add other routes for theyoder.family here as needed
      respond 404
      tls {
        dns cloudflare {$CLOUDFLARE_API_TOKEN}
      }
    '';
  };
}
