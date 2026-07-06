{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.caddy;
  vHosts = config.modules.services.vHosts.hosts;
in
{
  options.modules.services.infrastructure.caddy = {
    enable = mkEnableOption "Caddy reverse proxy with Cloudflare DNS";

    email = mkOption {
      type = types.str;
      default = "triston@7andco.studio";
      description = "Email for ACME certificate registration";
    };

    internalIpRanges = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" "::1" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "10.100.0.0/18" "100.64.0.0/10" "fd7a:115c:a1e0::/48" ];
      description = "IP ranges considered internal for private virtual hosts.";
    };

    cloudflareApiTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Cloudflare API token for DNS-01 challenge";
    };
  };

  config = mkIf cfg.enable {
    # Caddy with Cloudflare DNS and Security plugins
    services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [
          "github.com/caddy-dns/cloudflare@v0.2.1"
          "github.com/greenpau/caddy-security@v1.1.29"
        ];
        hash = "sha256-Sfem9E6lD6BYywQazUdH1qQOeg7vAjwgN3nCzFE/K9I=";
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
            resolvers 1.1.1.1 1.0.0.1
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

    services.caddy.virtualHosts = mkMerge (
      mapAttrsToList (_: hostCfg:
        let
          reverseProxyTarget =
            if hostCfg.reverseProxyAddress != null then
              hostCfg.reverseProxyAddress
            else
              "${if hostCfg.reverseProxySSL then "https" else "http"}://${hostCfg.reverseProxyHost}:${toString hostCfg.reverseProxyPort}";
        in
        # ipAddress vHosts are DNS-only (device handles its own TLS/serving); skip Caddy entirely
        mkIf (hostCfg.enable && hostCfg.ipAddress == null) {
          "${hostCfg.virtualHost}" = {
            serverAliases = hostCfg.serverAliases;
            extraConfig =
              if !hostCfg.rawConfig then
                ''
                  ${optionalString (!hostCfg.public) ''
                    @internal {
                      remote_ip ${concatStringsSep " " cfg.internalIpRanges}
                    }
                    handle @internal {
                      reverse_proxy ${reverseProxyTarget}
                    }
                    handle {
                      respond "Access Forbidden" 403
                    }
                  ''}
                  ${optionalString hostCfg.public ''
                    reverse_proxy ${reverseProxyTarget}
                  ''}
                  ${optionalString hostCfg.dnsChallenge "import cloudflare_tls"}
                  ${hostCfg.extraConfig}
                ''
              else
                ''
                  ${optionalString hostCfg.dnsChallenge "import cloudflare_tls"}
                  ${optionalString (!hostCfg.public) ''
                    @internal {
                      remote_ip ${concatStringsSep " " cfg.internalIpRanges}
                    }
                    handle @internal {
                      ${hostCfg.extraConfig}
                    }
                    handle {
                      respond "Access Forbidden" 403
                    }
                  ''}
                  ${optionalString hostCfg.public hostCfg.extraConfig}
                '';
          };
        })
      vHosts
    );
  };
}
