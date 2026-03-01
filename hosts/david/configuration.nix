# Configuration for david - Main Server
# Hosts all services including infrastructure, media, productivity, and storage

{ config, pkgs, lib, nixpkgs, nixpkgs-unstable, nix-bitcoin, ... }:
{
  imports = [
    ../../modules/services/tailscale-router.nix
  ];

  # =============================================================================
  # NETWORK: Bridge for Tailscale router container
  # =============================================================================
  # tailscale-router.nix creates br0 on enp4s0f0 with static 10.150.100.30/23,
  # and a container at 10.150.100.31/23 via macvlan.
  # Disable DHCP so the second NIC doesn't conflict.
  networking.useDHCP = lib.mkForce false;
  networking.interfaces.enp4s0f1.useDHCP = false;

  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "david";
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
      "@triston:${config.networking.domain}"
    ];
  };
  
  # iMessage Bridge - BlueBubbles configuration
  modules.services.communication.mautrix-imessage = {
    blueBubblesUrl = "http://macservices:1234";
    provisioningWhitelist = [
      "@triston:${config.networking.domain}"
    ];
  };
  
  # Stalwart Mail Server
  modules.services.communication.stalwart-mail.enable = false;

  # JellyPlex-Watched sync (continuous)
  modules.services.media.jellyplexWatched = {
    enable = true;
    plexTokenFile = config.age.secrets.plex-token.path;
    jellyfinTokenFile = config.age.secrets.jellyfin-token.path;
    extraEnv = {
      # Map Plex users to Jellyfin users when names don't match
      # Format: JSON dictionary { "plex_user": "jellyfin_user" }
      USER_MAPPING = ''{ "tristonyoder": "Triston Yoder" }'';
    };
  };
  
  # =============================================================================
  # CADDY CONFIGURATION FOR TECHNITIUM DNS
  # =============================================================================

  # Technitium DNS Web UI and DoH - dns01.<baseDomain>
  modules.services.vHosts."dns01.${config.networking.domain}" = {
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

  # Elizabeth Allen Photography - WordPress site
  modules.services.vHosts."elizabethallen.photography" = {
    public = true;
    reverseProxyPort = 1996;
  };

  # Dispatcharr - IPTV and stream management
  modules.services.vHosts."tv.${config.networking.domain}" = {
    reverseProxyPort = 9191;
  };

  # Threadfin - IPTV EPG proxy and M3U playlist management
  modules.services.vHosts."local-epg.tv.${config.networking.domain}" = {
    reverseProxyPort = 34400;
  };

  # InvokeAI
  modules.services.vHosts."invoke.${config.networking.domain}" = {
    reverseProxyHost = "tristons-workstation.${config.networking.domain}";
    reverseProxyPort = 9090;
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
