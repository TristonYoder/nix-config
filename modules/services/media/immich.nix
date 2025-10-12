{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.immich;
  
  # Helper function for Caddy virtual host with Cloudflare TLS
  cloudflareApiToken = 
    if config.age.secrets ? cloudflare-api-token
    then builtins.readFile config.age.secrets.cloudflare-api-token.path
    else "mDB6U0PcLl-QtjAlX5gskVgH4UO7_QMo5eLY0POq";  # Fallback during migration
  
  sharedTlsConfig = ''
    tls {
      dns cloudflare {
        api_token "${cloudflareApiToken}"
      }
    }
  '';
in
{
  options.modules.services.media.immich = {
    enable = mkEnableOption "Immich photo management";
    
    domain = mkOption {
      type = types.str;
      default = "photos.theyoder.family";
      description = "Primary domain for Immich";
    };
    
    publicProxyDomain = mkOption {
      type = types.str;
      default = "share.photos.theyoder.family";
      description = "Domain for public sharing proxy";
    };
    
    port = mkOption {
      type = types.port;
      default = 2283;
      description = "Immich server port";
    };
    
    publicProxyPort = mkOption {
      type = types.port;
      default = 2284;
      description = "Immich public proxy port";
    };
    
    mediaLocation = mkOption {
      type = types.str;
      default = "/data/docker-appdata/immich/media";
      description = "Location for media files";
    };
  };

  config = mkIf cfg.enable {
    # Immich service
    services.immich = {
      enable = true;
      port = cfg.port;
      openFirewall = true;
      host = "0.0.0.0";
      mediaLocation = cfg.mediaLocation;
      settings.server.externalDomain = "https://${cfg.domain}";
    };

    # Immich Public Proxy for sharing
    services.immich-public-proxy = {
      enable = true;
      immichUrl = "http://localhost:${toString cfg.port}/";
      openFirewall = true;
      port = cfg.publicProxyPort;
    };

    # Caddy virtual hosts
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        handle_path /share* {
          reverse_proxy http://localhost:${toString cfg.publicProxyPort}
        }
        handle {
          reverse_proxy http://localhost:${toString cfg.port}
        }
        ${sharedTlsConfig}
      '';
    };

    services.caddy.virtualHosts.${cfg.publicProxyDomain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.publicProxyPort}
        ${sharedTlsConfig}
      '';
    };
  };
}

