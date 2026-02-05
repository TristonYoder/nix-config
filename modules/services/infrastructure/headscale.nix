{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.headscale;
in
{
  # Admin UI imports (unconditional - each module has its own enable logic)
  imports = [
    ../../../docker/infrastructure/headscale/headplane.nix
    ../../../docker/infrastructure/headscale/headscale-admin.nix
    ../../../docker/infrastructure/headscale/headscale-console.nix
    ../../../docker/infrastructure/headscale/headscale-ui.nix
  ];

  options.modules.services.infrastructure.headscale = {
    enable = mkEnableOption "Headscale coordination server for Tailscale";

    # Domain Configuration
    baseDomain = mkOption {
      type = types.str;
      default = config.networking.domain;
      description = "Base domain for MagicDNS and service domains";
    };

    domain = mkOption {
      type = types.str;
      default = "ts.${cfg.baseDomain}";
      description = "Domain for headscale server (defaults to ts.baseDomain)";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Headscale API port";
    };

    serverUrl = mkOption {
      type = types.str;
      default = "https://${cfg.domain}";
      description = "Public URL for headscale server";
    };

    dns = mkOption {
      type = types.submodule {
        options = {
          searchDomains = mkOption {
            type = types.listOf types.str;
            default = unique [
              cfg.baseDomain
              config.networking.domain
              "7andco.studio"
              "7co.dev"
              "7andco.dev"
            ];
            description = "DNS search domains for Headscale clients";
          };
        };
      };
      default = {};
      description = "DNS configuration";
    };

    policy = mkOption {
      type = types.submodule {
        options = {
          path = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Path to policy file (null uses database-backed policy)";
          };

          mode = mkOption {
            type = types.enum [ "file" "database" ];
            default = "database";
            description = "Policy backend mode";
          };
        };
      };
      default = {};
      description = "Policy configuration";
    };

    # Database Configuration
    database = mkOption {
      type = types.submodule {
        options = {
          type = mkOption {
            type = types.enum [ "sqlite" "postgres" ];
            default = "sqlite";
            description = "Database backend (sqlite recommended by headscale upstream)";
          };

          path = mkOption {
            type = types.str;
            default = "/var/lib/headscale/db.sqlite";
            description = "Path to SQLite database file";
          };

          # PostgreSQL options (legacy support)
          host = mkOption {
            type = types.str;
            default = "localhost";
            description = "PostgreSQL host";
          };

          port = mkOption {
            type = types.port;
            default = 5432;
            description = "PostgreSQL port";
          };

          name = mkOption {
            type = types.str;
            default = "headscale";
            description = "PostgreSQL database name";
          };

          user = mkOption {
            type = types.str;
            default = "headscale";
            description = "PostgreSQL user";
          };

          passwordFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to PostgreSQL password file";
          };
        };
      };
      default = {};
      description = "Database configuration";
    };

    # OIDC Authentication (optional)
    oidc = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "OIDC authentication";

          issuer = mkOption {
            type = types.str;
            default = "";
            example = "https://id.theyoder.family";
            description = "OIDC issuer URL";
          };

          clientId = mkOption {
            type = types.str;
            default = "";
            example = "headscale";
            description = "OIDC client ID";
          };

          clientSecretFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to OIDC client secret file (from agenix)";
          };

          scope = mkOption {
            type = types.listOf types.str;
            default = [ "openid" "profile" "email" "groups" ];
            description = "OIDC scopes to request (includes groups for group-based access)";
          };

          allowedGroups = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [ "vpn_user" "headscale" ];
            description = "Restrict access to specific OIDC groups (PocketID group names)";
          };

          pkce = mkOption {
            type = types.submodule {
              options = {
                enabled = mkOption {
                  type = types.bool;
                  default = true;
                  description = "Enable PKCE (Proof Key for Code Exchange)";
                };

                method = mkOption {
                  type = types.enum [ "S256" "plain" ];
                  default = "S256";
                  description = "PKCE challenge method";
                };
              };
            };
            default = {};
            description = "PKCE configuration for enhanced security";
          };
        };
      };
      default = {};
      description = "OIDC authentication configuration";
    };

    # Admin UI Selection
    adminUI = mkOption {
      type = types.submodule {
        options = {
          type = mkOption {
            type = types.enum [ "none" "headplane" "admin" "console" "ui" ];
            default = "none";
            description = ''
              Admin UI type:
              - none: No admin UI
              - headplane: tale/headplane (feature-complete, OIDC support, recommended)
              - admin: GoodiesHQ/headscale-admin (simple, browser-based)
              - console: rickli-cloud/headscale-console (WebAssembly, SSH/VNC/RDP)
              - ui: simcu/headscale-ui (basic UI)
            '';
          };

          port = mkOption {
            type = types.port;
            default = 3000;
            description = "Admin UI internal port";
          };
        };
      };
      default = {};
      description = "Admin UI configuration";
    };

    # API Key (managed via agenix)
    apiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to headscale API key file (from agenix). If null, will be generated on first run.";
    };
  };

  config = mkIf cfg.enable {
    # Native NixOS headscale service
    services.headscale = {
      enable = true;
      address = "0.0.0.0";
      port = cfg.port;

      settings = {
        server_url = cfg.serverUrl;

        # Database configuration
        database = if cfg.database.type == "sqlite" then {
          type = "sqlite";
          sqlite = {
            path = cfg.database.path;
            write_ahead_log = true;
          };
        } else {
          type = "postgres";
          postgres = {
            host = cfg.database.host;
            port = cfg.database.port;
            name = cfg.database.name;
            user = cfg.database.user;
            password_file = cfg.database.passwordFile;
          };
        };

        # DNS settings with MagicDNS
        dns = {
          base_domain = cfg.baseDomain;
          magic_dns = true;
          nameservers = {
            global = [ "1.1.1.1" "1.0.0.1" ];
          };
          search_domains = unique cfg.dns.searchDomains;
        };

        policy = {
          path = cfg.policy.path;
          mode = cfg.policy.mode;
        };

        # OIDC configuration (if enabled)
        oidc = mkIf cfg.oidc.enable {
          issuer = cfg.oidc.issuer;
          client_id = cfg.oidc.clientId;
          client_secret_path = cfg.oidc.clientSecretFile;
          scope = cfg.oidc.scope;
          allowed_groups = cfg.oidc.allowedGroups;
          pkce = {
            enabled = cfg.oidc.pkce.enabled;
            method = cfg.oidc.pkce.method;
          };
        };

        # Default IP prefixes for Tailscale network
        prefixes = {
          v4 = "100.64.0.0/10";
          v6 = "fd7a:115c:a1e0::/48";
          allocation = "sequential";
        };

        # Disable logtail (Tailscale telemetry)
        logtail = {
          enabled = false;
        };

        # Log settings
        log = {
          level = "info";
          format = "text";
        };
      };
    };

    # API key generation service (only if apiKeyFile is null)
    systemd.services.headscale-api-key-init = mkIf (cfg.apiKeyFile == null) {
      description = "Generate headscale API key on first run";
      after = [ "headscale.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Check if API key already exists
        if [ ! -f /var/lib/headscale/.api-key-generated ]; then
          # Generate API key (90 day expiration)
          ${pkgs.headscale}/bin/headscale apikeys create --expiration 90d > /var/lib/headscale/api-key.txt
          chmod 600 /var/lib/headscale/api-key.txt
          chown headscale:headscale /var/lib/headscale/api-key.txt
          touch /var/lib/headscale/.api-key-generated

          echo "==================================================================="
          echo "Headscale API key generated. Please encrypt it with agenix:"
          echo "  On pits server:"
          echo "    sudo cat /var/lib/headscale/api-key.txt"
          echo ""
          echo "  On development machine (in nix-config/secrets):"
          echo "    ./encrypt-secret.sh -n headscale-api-key.age -s \"<paste-key-here>\" --git-add"
          echo ""
          echo "  The --git-add flag will automatically stage the encrypted file."
          echo "  Then commit and rebuild:"
          echo "    git commit -m \"Add headscale API key secret\""
          echo "    sudo nixos-rebuild switch --flake ."
          echo "==================================================================="
        fi
      '';
    };

    # Caddy reverse proxy for headscale API and admin UI
    modules.services.vHosts.${cfg.domain} = {
      managedProxy = false;
      extraConfig = ''
        ${optionalString (cfg.adminUI.type != "none") ''
        # Admin UI at /admin path
        handle /admin* {
          reverse_proxy http://localhost:${toString cfg.adminUI.port}
        }

        ''}# Headscale API for all other paths
        handle {
          reverse_proxy http://localhost:${toString cfg.port}
        }
      '';
    };
  };
}
