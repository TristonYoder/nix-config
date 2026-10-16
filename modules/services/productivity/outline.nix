{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.productivity.outline;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
  };
in
{
  options.modules.services.productivity.outline = {
    enable = mkEnableOption "Outline wiki and knowledge base";

    domain = mkOption {
      type = types.str;
      default = "outline.${config.networking.domain}";
      description = "Domain for Outline";
    };

    port = mkOption {
      type = types.port;
      # 3000 is Homepage's default
      default = 3020;
      description = "Port for Outline to listen on";
    };

    oidc = {
      issuer = mkOption {
        type = types.str;
        default = "https://id.${config.networking.domain}";
        description = "Pocket ID base URL";
      };

      clientId = mkOption {
        type = types.str;
        description = ''
          Client ID of the Outline OIDC client in Pocket ID. Its callback URL
          must be https://<domain>/auth/oidc.callback.
        '';
      };

      clientSecretFile = mkOption {
        type = types.str;
        default = config.age.secrets.outline-oidc-secret.path;
        description = "File containing the OIDC client secret";
      };
    };
  };

  config = mkIf cfg.enable {
    # Local PostgreSQL + Redis (unix socket), files under /var/lib/outline/data.
    # SECRET_KEY and UTILS_SECRET are generated on first start in /var/lib/outline.
    services.outline = {
      enable = true;
      # Track unstable while the deployment is new and still changing
      package = pkgs-unstable.outline;
      publicUrl = "https://${cfg.domain}";
      port = cfg.port;
      # Caddy terminates TLS
      forceHttps = false;
      storage.storageType = "local";
      oidcAuthentication = {
        inherit (cfg.oidc) clientId clientSecretFile;
        authUrl = "${cfg.oidc.issuer}/authorize";
        tokenUrl = "${cfg.oidc.issuer}/api/oidc/token";
        userinfoUrl = "${cfg.oidc.issuer}/api/oidc/userinfo";
        displayName = "Pocket ID";
      };
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Outline";
      category = "productivity";
      icon = "outline";
    };
  };
}
