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

    security = {
      enable = mkEnableOption "Caddy Security authentication and authorization";

      authPortal = {
        domain = mkOption {
          type = types.str;
          default = "auth.theyoder.family";
          description = "Domain for authentication portal";
        };

        tokenLifetime = mkOption {
          type = types.int;
          default = 86400;
          description = "JWT token lifetime in seconds (default: 24 hours)";
        };
      };

      oauthProviders = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            realm = mkOption {
              type = types.str;
              description = "Unique realm identifier for this OAuth provider";
            };

            clientIdFile = mkOption {
              type = types.path;
              description = "Path to file containing OAuth client_id (from agenix)";
            };

            clientSecretFile = mkOption {
              type = types.path;
              description = "Path to file containing OAuth client_secret (from agenix)";
            };

            baseAuthUrl = mkOption {
              type = types.str;
              default = "https://id.theyoder.family/authorize";
              description = "OIDC authorization endpoint";
            };

            metadataUrl = mkOption {
              type = types.str;
              default = "https://id.theyoder.family/.well-known/openid-configuration";
              description = "OIDC metadata endpoint";
            };

            scopes = mkOption {
              type = types.listOf types.str;
              default = [ "openid" "email" "profile" ];
              description = "OIDC scopes to request";
            };

            roleMapping = mkOption {
              type = types.listOf (types.submodule {
                options = {
                  group = mkOption {
                    type = types.str;
                    description = "Pocket ID group name";
                  };

                  role = mkOption {
                    type = types.str;
                    description = "Caddy Security role to assign (format: realm/user)";
                  };
                };
              });
              default = [];
              description = "Map Pocket ID groups to Caddy Security roles";
            };
          };
        });
        default = {};
        description = "OAuth identity providers configuration";
      };

      authorizationPolicies = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            authUrl = mkOption {
              type = types.str;
              description = "Authentication URL path (e.g., /caddy-security/oauth2/admin)";
            };

            allowedRoles = mkOption {
              type = types.listOf types.str;
              description = "Roles that are allowed access (format: realm/user)";
            };

            denyOthers = mkOption {
              type = types.bool;
              default = true;
              description = "Explicitly deny roles not in allowedRoles";
            };
          };
        });
        default = {};
        description = "Authorization policies for services";
      };
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

        ${optionalString cfg.security.enable ''
          # Caddy Security - Authentication and Authorization
          order authenticate before respond
          order authorize before basicauth

          security {
            ${concatStringsSep "\n    " (mapAttrsToList (name: provider: ''
              oauth identity provider ${name} {
                realm ${provider.realm}
                driver generic
                client_id {env.OAUTH_CLIENT_ID_${toUpper (replaceStrings ["-"] ["_"] name)}}
                client_secret {env.OAUTH_CLIENT_SECRET_${toUpper (replaceStrings ["-"] ["_"] name)}}
                scopes ${concatStringsSep " " provider.scopes}
                base_auth_url ${provider.baseAuthUrl}
                metadata_url ${provider.metadataUrl}
              }
            '') cfg.security.oauthProviders)}

            authentication portal authportal {
              crypto default token lifetime ${toString cfg.security.authPortal.tokenLifetime}
              ${concatStringsSep "\n      " (mapAttrsToList (name: provider:
                "enable identity provider ${name}"
              ) cfg.security.oauthProviders)}

              ${concatStringsSep "\n      " (flatten (mapAttrsToList (name: provider:
                map (mapping: ''
                  transform user {
                    match realm ${provider.realm}
                    match group ${mapping.group}
                    action add role ${mapping.role}
                  }
                '') provider.roleMapping
              ) cfg.security.oauthProviders))}
            }

            ${concatStringsSep "\n    " (mapAttrsToList (name: policy: ''
              authorization policy ${name} {
                set auth url ${policy.authUrl}
                ${concatMapStringsSep "\n      " (role: "allow roles ${role}") policy.allowedRoles}
                ${optionalString policy.denyOthers "deny"}
              }
            '') cfg.security.authorizationPolicies)}
          }
        ''}
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

    # Prepare OAuth credentials for Caddy Security
    systemd.services.caddy-prepare-oauth-env = mkIf cfg.security.enable {
      description = "Prepare OAuth credentials for Caddy Security";
      before = [ "caddy.service" ];
      requiredBy = [ "caddy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/caddy
        touch /run/caddy/oauth.env
        chmod 600 /run/caddy/oauth.env

        ${concatStringsSep "\n    " (mapAttrsToList (name: provider:
          let
            upperName = toUpper (replaceStrings ["-"] ["_"] name);
          in ''
            CLIENT_ID=$(cat ${provider.clientIdFile})
            CLIENT_SECRET=$(cat ${provider.clientSecretFile})
            echo "OAUTH_CLIENT_ID_${upperName}=$CLIENT_ID" >> /run/caddy/oauth.env
            echo "OAUTH_CLIENT_SECRET_${upperName}=$CLIENT_SECRET" >> /run/caddy/oauth.env
          ''
        ) cfg.security.oauthProviders)}

        chown caddy:caddy /run/caddy/oauth.env
      '';
    };

    # Configure Caddy service to load the formatted environment files
    systemd.services.caddy.serviceConfig = {
      EnvironmentFile = [
        "/run/caddy/cloudflare.env"
      ] ++ optional cfg.security.enable "/run/caddy/oauth.env";
    };

    # Authentication portal virtual host
    services.caddy.virtualHosts.${cfg.security.authPortal.domain} = mkIf cfg.security.enable {
      extraConfig = ''
        @auth {
          path /caddy-security/*
        }

        route @auth {
          authenticate with authportal
        }

        import cloudflare_tls
      '';
    };

    # Open firewall ports for HTTP and HTTPS
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}

