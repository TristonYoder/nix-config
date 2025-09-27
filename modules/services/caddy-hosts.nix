{ config, lib, pkgs, ... }:

let
  # Cloudflare API Token - should be moved to secrets management
  cloudflareApiToken = "mDB6U0PcLl-QtjAlX5gskVgH4UO7_QMo5eLY0POq";
  
  # Helper function to create a virtual host with reverse proxy and TLS
  createVirtualHost = target: ''
    reverse_proxy ${target}
    ${sharedTlsConfig}
  '';
  
  # Shared TLS configuration for custom virtual hosts
  sharedTlsConfig = ''
    tls {
      dns cloudflare {
        api_token "${cloudflareApiToken}"
      }
    }
  '';
in
{
  # =============================================================================
  # CADDY VIRTUAL HOSTS - Services without corresponding NixOS services
  # =============================================================================

  # General Apps (no specific service)
  services.caddy.virtualHosts."apps.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:7575";
  };

  # Bitcoin Services (external services)
  services.caddy.virtualHosts."btc.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:8997";
  };

  services.caddy.virtualHosts."mempool.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:8998";
  };

  # Website Services (Docker services)
  services.caddy.virtualHosts."carolineyoder.com" = {
    extraConfig = createVirtualHost "http://localhost:1128";
  };

  services.caddy.virtualHosts."carolineelizabeth.photography elizabethallen.photography carolines.photos takemy.photo loveinfocus.photography" = {
    extraConfig = createVirtualHost "http://localhost:1996";
  };

  # Chat Services (commented out Mattermost)
  services.caddy.virtualHosts."chat.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:8065";
  };

  # ErsatzTV (Docker service)
  services.caddy.virtualHosts."tv.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:8409";
  };

  # Home Assistant (external service)
  services.caddy.virtualHosts."home.theyoder.family" = {
    extraConfig = createVirtualHost "http://10.150.2.117:8123";
  };

  # Notes Services (Docker service)
  services.caddy.virtualHosts."notes.theyoder.family notes.7andco.studio" = {
    extraConfig = createVirtualHost "http://localhost:3010";
  };

  # Social Services (commented out Mastodon)
  services.caddy.virtualHosts."social.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:55001";
  };

  # Planning Poker (Docker service)
  services.caddy.virtualHosts."poker.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:8234";
  };

  # Recipe Services (Docker service)
  services.caddy.virtualHosts."recipies.theyoder.family food.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:6780";
  };

  # UniFi (external service)
  services.caddy.virtualHosts."unifi.theyoder.family" = {
    extraConfig = ''
      reverse_proxy https://10.150.100.1 {
        transport http {
          tls
          tls_insecure_skip_verify
        }
      }
      ${sharedTlsConfig}
    '';
  };

  # Special Cases
  services.caddy.virtualHosts."david.theyoder.family" = {
    extraConfig = ''
      respond "404" 404
      ${sharedTlsConfig}
    '';
  };
}
