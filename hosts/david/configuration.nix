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

  # dns-sync: use local Technitium directly (avoids Caddy loopback for the API)
  modules.services.vHosts.technitium.url = "http://localhost:5380";

  # Navidrome - Music streaming server (Subsonic-compatible)
  modules.services.media.navidrome.enable = true;

  # Feishin - Web music player (Jellyfin/Navidrome/Subsonic client)
  modules.services.media.feishin.enable = true;

  # Beets - Auto-organize music library from Downloads into Music
  modules.services.media.beets.enable = true;

  # Music dedup - Daily hard-link deduplication of the music library
  modules.services.media.musicDedup.enable = true;

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
  modules.services.vHosts.hosts."dns01.${config.networking.domain}" = {
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
  modules.services.vHosts.hosts."elizabethallen.photography" = {
    public = true;
    reverseProxyPort = 1996;
  };

  # Tunarr - Virtual IPTV tuner for Plex/Jellyfin
  modules.services.vHosts.hosts."tunarr.${config.networking.domain}" = {
    reverseProxyPort = 8100;
  };

  # Dispatcharr - IPTV and stream management
  modules.services.vHosts.hosts."tv.${config.networking.domain}" = {
    reverseProxyPort = 9191;
  };

  # Threadfin - IPTV EPG proxy and M3U playlist management
  modules.services.vHosts.hosts."local-epg.tv.${config.networking.domain}" = {
    reverseProxyPort = 34400;
  };

  # Tidarr - Tidal music downloader
  modules.services.vHosts.hosts."tidal.${config.networking.domain}" = {
    reverseProxyPort = 8484;
  };

  # InvokeAI
  modules.services.vHosts.hosts."invoke.${config.networking.domain}" = {
    reverseProxyHost = "tristons-workstation.${config.networking.domain}";
    reverseProxyPort = 9090;
  };

  # =============================================================================
  # CAMPUS STAGE DISPLAYS
  # =============================================================================

  services.stage-display.enable = true;

  modules.services.vHosts.hosts."stage.${config.networking.domain}" = {
    reverseProxyPort = 7474;
  };

  # =============================================================================
  # STORAGE: USB Drive Sync
  # =============================================================================

  modules.services.storage.wiiHddSync.enable = true;

  modules.services.storage.mp3PlayerSync = {
    enable = true;
    uuid = "EC95-4FBB";
    jellyfinApiKeyFile = config.age.secrets.jellyfin-api-key.path;
    playlists = [
      "Judah's MP3 Player"
    ];
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
