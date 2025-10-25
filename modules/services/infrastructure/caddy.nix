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
        
        # Bind to both IPv4 and IPv6
        servers {
          protocols h1 h2 h3
        }
      '';
      extraConfig = ''
        # Cloudflare TLS snippet for reuse across virtual hosts
        # Note: Snippets must be defined at top level, outside global config block
        (cloudflare_tls) {
          tls {
            dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          }
        }
      '';
    };

    # Create a systemd service that prepares the Cloudflare API token environment file
    # The agenix secret contains only the raw token value (cleaner secret management)
    # We wrap it in KEY=VALUE format at runtime for systemd's EnvironmentFile
    systemd.services.caddy-prepare-env = {
      description = "Prepare Cloudflare API token for Caddy";
      before = [ "caddy.service" ];
      requiredBy = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Read the raw token from agenix secret and format it for systemd EnvironmentFile
        TOKEN=$(cat ${config.age.secrets.cloudflare-api-token.path})
        mkdir -p /run/caddy
        echo "CLOUDFLARE_API_TOKEN=$TOKEN" > /run/caddy/cloudflare.env
        chmod 600 /run/caddy/cloudflare.env
        chown caddy:caddy /run/caddy/cloudflare.env
      '';
    };

    # Configure Caddy service to load the formatted environment file
    systemd.services.caddy.serviceConfig = {
      EnvironmentFile = "/run/caddy/cloudflare.env";
    };

    # Open firewall ports for HTTP and HTTPS
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}

