{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.caddy;
  ssoCfg = config.modules.services.vHosts.sso;
  vHosts = recursiveUpdate cfg.virtualHosts config.modules.services.vHosts.hosts;
  ssoHosts = filterAttrs (_: h: h.enable && h.sso.enable) vHosts;
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

    virtualHosts = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to create this virtual host.";
          };

          virtualHost = mkOption {
            type = types.str;
            default = name;
            description = "Virtual host name (defaults to the attribute key).";
          };

          reverseProxyAddress = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Explicit upstream reverse proxy target (overrides host/port/SSL if set).";
          };

          reverseProxyHost = mkOption {
            type = types.str;
            default = "localhost";
            description = "Reverse proxy host (defaults to the local machine).";
          };

          reverseProxyPort = mkOption {
            type = types.port;
            default = 80;
            description = "Reverse proxy port.";
          };

          reverseProxySSL = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to use HTTPS when building the reverse proxy address.";
          };

          managedProxy = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to use the managed reverse proxy template.";
          };

          public = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the virtual host should be publicly accessible.";
          };

          dnsRecord = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to include this virtual host in managed DNS records.";
          };

          dnsChallenge = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to enable DNS-01 TLS for this host (uses Cloudflare snippet).";
          };

          serverAliases = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional hostnames served by this virtual host.";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "Additional Caddy config appended to this virtual host.";
          };
        };
      }));
      default = { };
      description = "Caddy virtual host definitions managed by the infrastructure module.";
    };

    dnsRecords = mkOption {
      type = types.listOf types.str;
      default = [ ];
      readOnly = true;
      description = "List of virtual hosts requesting DNS records (for future automation).";
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
        hash = "sha256-ViyxE9sdsoc9S1S/Odgf97meIzyp7z6FK1OWGP3LBmg=";
      };
      globalConfig = ''
        email ${cfg.email}

        # Bind to both IPv4 and IPv6
        servers {
          protocols h1 h2 h3
        }
      '' + optionalString ssoCfg.enable ''

        security {
          oauth identity provider pocket_id {
            realm pocket_id
            driver generic
            client_id ${ssoCfg.clientId}
            client_secret {env.CADDY_SSO_CLIENT_SECRET}
            scopes openid email profile groups
            base_auth_url ${ssoCfg.pocketIdUrl}
            metadata_url ${ssoCfg.pocketIdUrl}/.well-known/openid-configuration
          }

          authentication portal main {
            crypto default token lifetime 86400
            crypto key sign-verify {env.CADDY_SSO_JWT_SECRET}
            enable identity provider pocket_id
            cookie domain ${ssoCfg.cookieDomain}
          }

          ${concatStringsSep "\n\n          " (mapAttrsToList (_: hostCfg:
            let
              allowClause =
                if hostCfg.sso.allowedGroups == []
                then "allow roles authp/user authp/admin"
                else concatStringsSep "\n          " (map (g: "allow groups ${g}") hostCfg.sso.allowedGroups);
            in
            ''
              authorization policy ${hostCfg.sso.policyName}_policy {
                set auth url https://${ssoCfg.portalDomain}
                ${allowClause}
                validate bearer header
                inject headers with claims
              }''
          ) ssoHosts)}
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

    systemd.services.caddy-prepare-env = {
      description = "Prepare Caddy environment secrets";
      before = [ "caddy.service" ];
      requiredBy = [ "caddy.service" ];
      after = [ "agenix.service" ];
      wants = [ "agenix.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/caddy
        echo "CLOUDFLARE_API_TOKEN=$(cat ${config.age.secrets.cloudflare-api-token.path})" > /run/caddy/caddy.env
        ${optionalString ssoCfg.enable ''
          echo "CADDY_SSO_CLIENT_SECRET=$(cat ${toString ssoCfg.clientSecretFile})" >> /run/caddy/caddy.env
          echo "CADDY_SSO_JWT_SECRET=$(cat ${toString ssoCfg.jwtSecretFile})" >> /run/caddy/caddy.env
        ''}
        chmod 600 /run/caddy/caddy.env
        chown caddy:caddy /run/caddy/caddy.env
      '';
    };

    systemd.services.caddy.serviceConfig = {
      EnvironmentFile = "/run/caddy/caddy.env";
    };

    # Auto-register the SSO auth portal as a vHost (DNS sync picks it up too)
    modules.services.vHosts.hosts = mkIf ssoCfg.enable {
      "${ssoCfg.portalDomain}" = {
        managedProxy = false;
        public = false;
        extraConfig = "authenticate with main";
      };
    };

    # Open firewall ports for HTTP and HTTPS
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    modules.services.infrastructure.caddy.dnsRecords =
      map (host: host.virtualHost)
        (filter (host: host.dnsRecord)
          (attrValues vHosts));

    services.caddy.virtualHosts = mkMerge (
      mapAttrsToList (_: hostCfg:
        let
          reverseProxyTarget =
            if hostCfg.reverseProxyAddress != null then
              hostCfg.reverseProxyAddress
            else
              "${if hostCfg.reverseProxySSL then "https" else "http"}://${hostCfg.reverseProxyHost}:${toString hostCfg.reverseProxyPort}";
          proxyDirectives =
            if hostCfg.sso.enable then ''
              authorize with ${hostCfg.sso.policyName}_policy
              reverse_proxy ${reverseProxyTarget}
            '' else ''
              reverse_proxy ${reverseProxyTarget}
            '';
        in
        mkIf hostCfg.enable {
          "${hostCfg.virtualHost}" = {
            serverAliases = hostCfg.serverAliases;
            extraConfig =
              if hostCfg.managedProxy then
                ''
                  ${optionalString (!hostCfg.public) ''
                    @internal {
                      remote_ip ${concatStringsSep " " cfg.internalIpRanges}
                    }
                    handle @internal {
                      ${proxyDirectives}
                    }
                    handle {
                      respond "Access Forbidden" 403
                    }
                  ''}
                  ${optionalString hostCfg.public proxyDirectives}
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
