{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.headscale;
in
{
  config = mkIf (cfg.enable && cfg.adminUI.type == "console") {
    # Docker runtime
    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";

    # headscale-console container
    virtualisation.oci-containers.containers."headscale-console" = {
      image = "ghcr.io/rickli-cloud/headscale-console:latest";

      environment = {
        HEADSCALE_URL = "http://localhost:${toString cfg.port}";
      };

      volumes = if cfg.apiKeyFile != null then [
        "${cfg.apiKeyFile}:/etc/headscale-console/api-key:ro"
      ] else [];

      ports = [
        "${toString cfg.adminUI.port}:3000/tcp"
      ];

      extraOptions = [
        "--network=host"
      ];

      log-driver = "journald";
    };

    # Systemd service
    systemd.services."docker-headscale-console" = {
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
  };
}
