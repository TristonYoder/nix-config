{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.headscale;
in
{
  config = mkIf (cfg.enable && cfg.adminUI.type == "admin") {
    # Docker runtime
    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";

    # headscale-admin container
    # Note: This is a static web UI - config happens in browser via localStorage
    virtualisation.oci-containers.containers."headscale-admin" = {
      image = "goodieshq/headscale-admin:latest";

      ports = [
        "${toString cfg.adminUI.port}:80/tcp"
      ];

      log-driver = "journald";
    };

    # Systemd service
    systemd.services."docker-headscale-admin" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
      };
      after = [ "headscale.service" ];
      requires = [ "headscale.service" ];
      wantedBy = [ "multi-user.target" ];
    };

    # Override Caddy virtual host to add CORS headers for headscale-admin
    # Since we're using path-based routing, we need to override the main definition
    services.caddy.virtualHosts.${cfg.domain} =
      mkIf config.modules.services.infrastructure.caddy.enable (mkForce {
        extraConfig = ''
          # CORS headers for headscale-admin (browser-based UI needs CORS)
          header Access-Control-Allow-Origin "https://${cfg.domain}"
          header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
          header Access-Control-Allow-Headers "Authorization, Content-Type"
          header Access-Control-Allow-Credentials "true"

          # Admin UI at /admin path
          handle /admin* {
            reverse_proxy http://localhost:${toString cfg.adminUI.port}
          }

          # Headscale API for all other paths
          handle {
            reverse_proxy http://localhost:${toString cfg.port}
          }

          import cloudflare_tls
        '';
      });
  };
}
