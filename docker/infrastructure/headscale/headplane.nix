{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.headscale;
in
{
  config = mkIf (cfg.enable && cfg.adminUI.type == "headplane") {
    # Docker runtime
    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";

    # Headplane configuration file
    environment.etc."headscale/headplane-config.yaml" = {
      text = ''
        server:
          host: 0.0.0.0
          port: ${toString cfg.adminUI.port}
          cookie_secret_path: ${if cfg.apiKeyFile != null then cfg.apiKeyFile else "/var/lib/headscale/api-key.txt"}
          cookie_secure: true  # Use secure cookies (requires HTTPS via Caddy)

        headscale:
          url: http://localhost:${toString cfg.port}
          config_strict: false  # Allow non-strict config validation

        ${optionalString cfg.oidc.enable ''
        oidc:
          enabled: true
          issuer: ${cfg.oidc.issuer}
          client_id: ${cfg.oidc.clientId}
          client_secret_path: ${cfg.oidc.clientSecretFile}
          headscale_api_key_path: ${if cfg.apiKeyFile != null then cfg.apiKeyFile else "/var/lib/headscale/api-key.txt"}
          disable_api_key_login: false  # Allow both OIDC and API key login
          token_endpoint_auth_method: client_secret_post  # PocketID uses POST method
        ''}
      '';
      mode = "0644";
    };

    # Headplane container
    virtualisation.oci-containers.containers."headplane" = {
      image = "ghcr.io/tale/headplane:latest";

      volumes = [
        "/etc/headscale/headplane-config.yaml:/etc/headplane/config.yaml:ro"
        "headplane-data:/var/lib/headplane:rw"
      ] ++ (optional (cfg.apiKeyFile != null) "${cfg.apiKeyFile}:${cfg.apiKeyFile}:ro")
        ++ (optional (cfg.oidc.enable && cfg.oidc.clientSecretFile != null) "${cfg.oidc.clientSecretFile}:${cfg.oidc.clientSecretFile}:ro");

      ports = [
        "${toString cfg.adminUI.port}:${toString cfg.adminUI.port}/tcp"
      ];

      extraOptions = [
        "--network=host"  # Use host network for localhost access to headscale
      ];

      log-driver = "journald";
    };

    # Systemd service
    systemd.services."docker-headplane" = {
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

    # Docker volume
    systemd.services."docker-volume-headplane-data" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        docker volume inspect headplane-data || docker volume create headplane-data
      '';
      wantedBy = [ "docker-headplane.service" ];
      before = [ "docker-headplane.service" ];
    };
  };
}
