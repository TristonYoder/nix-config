{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.development.code-server;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };

  # Helper to generate systemd service name for instance
  instanceServiceName = name: "code-server-${name}";

  # Helper to generate policy name
  instancePolicyName = name: "code_server_${name}_access";
in
{
  options.modules.services.development.code-server = {
    enable = mkEnableOption "code-server for web-based VS Code development";

    instances = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Enable this code-server instance";
          };

          domain = mkOption {
            type = types.str;
            description = "Domain for this code-server instance";
            example = "vscode.7co.dev";
          };

          port = mkOption {
            type = types.port;
            description = "Port for this code-server instance";
            example = 11010;
          };

          user = mkOption {
            type = types.str;
            default = "tristonyoder";
            description = "User to run code-server as";
          };

          host = mkOption {
            type = types.str;
            default = "127.0.0.1";
            description = "Host address to bind to";
          };

          auth = mkOption {
            type = types.enum [ "password" "none" ];
            default = "none";
            description = "Authentication method (use 'none' with OIDC)";
          };

          caddyOIDC = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable OIDC authentication for this instance";
            };

            realm = mkOption {
              type = types.str;
              default = "code-server";
              description = "OIDC realm identifier";
            };

            allowedGroups = mkOption {
              type = types.listOf types.str;
              default = [];
              description = "Pocket ID groups allowed to access this instance";
              example = [ "admin" "developer" ];
            };
          };
        };
      }));
      default = {};
      description = "code-server instance configurations";
    };

    # Backward compatibility options (deprecated)
    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "DEPRECATED: Use instances instead";
    };

    port = mkOption {
      type = types.nullOr types.port;
      default = null;
      description = "DEPRECATED: Use instances instead";
    };

    host = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "DEPRECATED: Use instances instead";
    };

    user = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "DEPRECATED: Use instances instead";
    };

    auth = mkOption {
      type = types.nullOr (types.enum [ "password" "none" ]);
      default = null;
      description = "DEPRECATED: Use instances instead";
    };
  };

  config = mkIf cfg.enable {
    # Declare agenix secrets for OIDC (only when OIDC is enabled)
    age.secrets.pocket-id-client-code-server-id = mkIf (any (inst: inst.caddyOIDC.enable) (attrValues cfg.instances)) {
      file = ../../../secrets/pocket-id-client-code-server-id.age;
    };

    age.secrets.pocket-id-client-code-server-secret = mkIf (any (inst: inst.caddyOIDC.enable) (attrValues cfg.instances)) {
      file = ../../../secrets/pocket-id-client-code-server-secret.age;
    };

    # Backward compatibility: migrate old options to instances.default
    modules.services.development.code-server.instances.default = mkIf (cfg.domain != null) {
      enable = true;
      domain = mkDefault cfg.domain;
      port = mkDefault (if cfg.port != null then cfg.port else 11010);
      host = mkDefault (if cfg.host != null then cfg.host else "127.0.0.1");
      user = mkDefault (if cfg.user != null then cfg.user else "tristonyoder");
      auth = mkDefault (if cfg.auth != null then cfg.auth else "none");
    };

    # Generate systemd services for each instance
    systemd.services = mapAttrs' (name: instanceCfg:
      nameValuePair (instanceServiceName name) (mkIf instanceCfg.enable {
        description = "code-server instance: ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = {
          HOME = "/home/${instanceCfg.user}";
        };

        serviceConfig = {
          Type = "simple";
          User = instanceCfg.user;
          ExecStart = ''
            ${pkgs-unstable.code-server}/bin/code-server \
              --bind-addr ${instanceCfg.host}:${toString instanceCfg.port} \
              --auth ${instanceCfg.auth}
          '';
          Restart = "on-failure";
          RestartSec = "10s";
        };
      })
    ) cfg.instances;

    # Configure Caddy Security OAuth providers for instances with OIDC
    modules.services.infrastructure.caddy.security.oauthProviders =
      mapAttrs' (name: instanceCfg:
        nameValuePair "code_server_${name}" (mkIf instanceCfg.caddyOIDC.enable {
          realm = instanceCfg.caddyOIDC.realm;
          clientIdFile = config.age.secrets.pocket-id-client-code-server-id.path;
          clientSecretFile = config.age.secrets.pocket-id-client-code-server-secret.path;
          roleMapping = map (group: {
            group = group;
            role = "${instanceCfg.caddyOIDC.realm}/user";
          }) instanceCfg.caddyOIDC.allowedGroups;
        })
      ) cfg.instances;

    # Configure Caddy Security authorization policies
    modules.services.infrastructure.caddy.security.authorizationPolicies =
      mapAttrs' (name: instanceCfg:
        nameValuePair (instancePolicyName name) (mkIf instanceCfg.caddyOIDC.enable {
          authUrl = "/caddy-security/oauth2/${instanceCfg.caddyOIDC.realm}";
          allowedRoles = [ "${instanceCfg.caddyOIDC.realm}/user" ];
          denyOthers = true;
        })
      ) cfg.instances;

    # Configure Caddy virtual hosts
    services.caddy.virtualHosts = mapAttrs' (name: instanceCfg:
      nameValuePair instanceCfg.domain (mkIf instanceCfg.enable {
        extraConfig = ''
          ${optionalString instanceCfg.caddyOIDC.enable ''
            @auth {
              path /caddy-security/*
            }

            route @auth {
              authenticate with authportal
            }

            route /* {
              authorize with ${instancePolicyName name}
              reverse_proxy http://${instanceCfg.host}:${toString instanceCfg.port}
            }
          ''}
          ${optionalString (!instanceCfg.caddyOIDC.enable) ''
            reverse_proxy http://${instanceCfg.host}:${toString instanceCfg.port}
          ''}
          import cloudflare_tls
        '';
      })
    ) cfg.instances;

    # Enable Caddy Security when any instance uses OIDC
    modules.services.infrastructure.caddy.security.enable =
      mkIf (any (inst: inst.caddyOIDC.enable) (attrValues cfg.instances)) true;
  };
}
