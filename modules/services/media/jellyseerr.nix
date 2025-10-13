{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.jellyseerr;
  
  # Caddy virtual host configuration with Cloudflare DNS TLS
  sharedTlsConfig = ''
    tls {
      dns cloudflare {
        api_token "${builtins.readFile config.age.secrets.cloudflare-api-token.path}"
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

