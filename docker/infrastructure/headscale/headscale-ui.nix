{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.headscale;
in
{
  config = mkIf (cfg.enable && cfg.adminUI.type == "ui") {
    # Docker runtime
    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";

    # headscale-ui container
    virtualisation.oci-containers.containers."headscale-ui" = {
      image = "ghcr.io/simcu/headscale-ui:latest";

      environment = {
        HEADSCALE_API_URL = "http://localhost:${toString cfg.port}";
        HEADSCALE_API_KEY_FILE = "/run/secrets/api-key";
      };

      volumes = if cfg.apiKeyFile != null then [
        "${cfg.apiKeyFile}:/run/secrets/api-key:ro"
      ] else [];

      ports = [
        "${toString cfg.adminUI.port}:80/tcp"
      ];

      extraOptions = [
        "--network=host"
      ];

      log-driver = "journald";
    };

    # Systemd service
    systemd.services."docker-headscale-ui" = {
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
