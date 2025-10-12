{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.jellyseerr;
  
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
  options.modules.services.media.jellyseerr = {
    enable = mkEnableOption "Jellyseerr media request management";
    
    domains = mkOption {
      type = types.listOf types.str;
      default = [ "request.theyoder.family" "requests.theyoder.family" ];
      description = "Domains for Jellyseerr (space-separated in Caddy config)";
    };
    
    port = mkOption {
      type = types.port;
      default = 5055;
      description = "Jellyseerr port";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port";
    };
  };

  config = mkIf cfg.enable {
    # Jellyseerr service
    services.jellyseerr = {
      enable = true;
      openFirewall = cfg.openFirewall;
      port = cfg.port;
    };

    # Caddy virtual host (supports multiple domains)
    services.caddy.virtualHosts."${concatStringsSep " " cfg.domains}" = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.port}
        ${sharedTlsConfig}
      '';
    };
  };
}

