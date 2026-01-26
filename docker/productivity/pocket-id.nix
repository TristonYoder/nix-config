# Pocket ID - Lightweight identity and access management
# Self-hosted authentication service for easy identity management
# Requires ENCRYPTION_KEY secret set in agenix
{ config, pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."pocket-id-pocket-id" = {
    image = "ghcr.io/pocket-id/pocket-id:v2";
    environmentFiles = [
      config.age.secrets.pocket-id-encryption-key.path
    ];
    environment = {
      "APP_URL" = "https://id.theyoder.family";
      "TRUST_PROXY" = "true";
      "PUID" = "1000";
      "PGID" = "1000";
    };
    volumes = [
      "pocket-id_data:/app/data:rw"
    ];
    ports = [
      "1411:1411/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=pocket-id"
      "--network=pocket-id_default"
    ];
  };

  systemd.services."docker-pocket-id-pocket-id" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "10s";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-pocket-id_default.service"
      "docker-volume-pocket-id_data.service"
    ];
    requires = [
      "docker-network-pocket-id_default.service"
      "docker-volume-pocket-id_data.service"
    ];
    partOf = [
      "docker-compose-pocket-id-root.target"
    ];
    wantedBy = [
      "docker-compose-pocket-id-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-pocket-id_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f pocket-id_default";
    };
    script = ''
      docker network inspect pocket-id_default || docker network create pocket-id_default
    '';
    partOf = [ "docker-compose-pocket-id-root.target" ];
    wantedBy = [ "docker-compose-pocket-id-root.target" ];
  };

  # Volumes
  systemd.services."docker-volume-pocket-id_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect pocket-id_data || docker volume create pocket-id_data
    '';
    partOf = [ "docker-compose-pocket-id-root.target" ];
    wantedBy = [ "docker-compose-pocket-id-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-pocket-id-root" = {
    unitConfig = {
      Description = "Pocket ID identity and access management service";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Caddy reverse proxy
  services.caddy.virtualHosts."id.theyoder.family" = {
    extraConfig = ''
      reverse_proxy http://localhost:1411 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
      }

      import cloudflare_tls
    '';
  };
}
