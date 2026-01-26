{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.pocket-id;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  options.modules.services.infrastructure.pocket-id = {
    enable = mkEnableOption "Pocket ID authentication service";

    domain = mkOption {
      type = types.str;
      default = "id.theyoder.family";
      description = "Domain for Pocket ID";
    };

    port = mkOption {
      type = types.port;
      default = 3002;
      description = "Pocket ID port";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/pocket-id/data";
      description = "Data directory for Pocket ID";
    };

    trustProxy = mkOption {
      type = types.bool;
      default = true;
      description = "Trust proxy headers for Pocket ID";
    };

    analyticsDisabled = mkOption {
      type = types.bool;
      default = true;
      description = "Disable analytics in Pocket ID";
    };
  };

  config = mkIf cfg.enable {
    services.pocket-id = {
      enable = true;
      package = pkgs-unstable.pocket-id;
      dataDir = cfg.dataDir;
      settings = {
        APP_URL = "https://${cfg.domain}";
        TRUST_PROXY = cfg.trustProxy;
        ANALYTICS_DISABLED = cfg.analyticsDisabled;
        PORT = cfg.port;
      };
    };

    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.port} {
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
        }

        import cloudflare_tls
      '';
    };
  };
}
