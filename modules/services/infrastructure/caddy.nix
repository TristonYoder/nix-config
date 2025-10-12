{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.caddy;
in
{
  options.modules.services.infrastructure.caddy = {
    enable = mkEnableOption "Caddy reverse proxy with Cloudflare DNS";
    
    email = mkOption {
      type = types.str;
      default = "triston@7andco.studio";
      description = "Email for ACME certificate registration";
    };
    
    cloudflareApiTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Cloudflare API token for DNS-01 challenge";
    };
  };

  config = mkIf cfg.enable {
    # Caddy with Cloudflare DNS plugin
    services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
        hash = "sha256-p9AIi6MSWm0umUB83HPQoU8SyPkX5pMx989zAi8d/74=";
      };
      globalConfig = ''
        email ${cfg.email}
      '';
      extraConfig = ''
        # Global configuration can go here
      '';
    };

    # Open firewall ports for HTTP and HTTPS
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}

