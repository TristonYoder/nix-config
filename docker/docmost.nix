# Auto-generated using compose2nix v0.3.1.
{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."docmost-db" = {
    image = "postgres:16-alpine";
    environment = {
      "POSTGRES_DB" = "docmost";
      "POSTGRES_PASSWORD" = "{a_secret_was_here}";
      "POSTGRES_USER" = "docmost";
    };
    volumes = [
      "docmost_db_data:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=db"
      "--network=docmost_default"
    ];
  };
  systemd.services."docker-docmost-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-docmost_default.service"
      "docker-volume-docmost_db_data.service"
    ];
    requires = [
      "docker-network-docmost_default.service"
      "docker-volume-docmost_db_data.service"
    ];
    partOf = [
      "docker-compose-docmost-root.target"
    ];
    wantedBy = [
      "docker-compose-docmost-root.target"
    ];
  };
  virtualisation.oci-containers.containers."docmost-docmost" = {
    image = "docmost/docmost:latest";
    environment = {
      "APP_SECRET" = "{a_secret_was_here}";
      "APP_URL" = "http://david:6590";
      "DATABASE_URL" = "postgresql://docmost:{a_secret_was_here}@db:5432/docmost?schema=public";
      "REDIS_URL" = "redis://redis:6379";
    };
    volumes = [
      "docmost_docmost:/app/data/storage:rw"
    ];
    ports = [
      "6590:3000/tcp"
    ];
    dependsOn = [
      "docmost-db"
      "docmost-redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=docmost"
      "--network=docmost_default"
    ];
  };
  systemd.services."docker-docmost-docmost" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-docmost_default.service"
      "docker-volume-docmost_docmost.service"
    ];
    requires = [
      "docker-network-docmost_default.service"
      "docker-volume-docmost_docmost.service"
    ];
    partOf = [
      "docker-compose-docmost-root.target"
    ];
    wantedBy = [
      "docker-compose-docmost-root.target"
    ];
  };
  virtualisation.oci-containers.containers."docmost-redis" = {
    image = "redis:7.2-alpine";
    volumes = [
      "docmost_redis_data:/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=redis"
      "--network=docmost_default"
    ];
  };
  systemd.services."docker-docmost-redis" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-docmost_default.service"
      "docker-volume-docmost_redis_data.service"
    ];
    requires = [
      "docker-network-docmost_default.service"
      "docker-volume-docmost_redis_data.service"
    ];
    partOf = [
      "docker-compose-docmost-root.target"
    ];
    wantedBy = [
      "docker-compose-docmost-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-docmost_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f docmost_default";
    };
    script = ''
      docker network inspect docmost_default || docker network create docmost_default
    '';
    partOf = [ "docker-compose-docmost-root.target" ];
    wantedBy = [ "docker-compose-docmost-root.target" ];
  };

  # Volumes
  systemd.services."docker-volume-docmost_db_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect docmost_db_data || docker volume create docmost_db_data
    '';
    partOf = [ "docker-compose-docmost-root.target" ];
    wantedBy = [ "docker-compose-docmost-root.target" ];
  };
  systemd.services."docker-volume-docmost_docmost" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect docmost_docmost || docker volume create docmost_docmost
    '';
    partOf = [ "docker-compose-docmost-root.target" ];
    wantedBy = [ "docker-compose-docmost-root.target" ];
  };
  systemd.services."docker-volume-docmost_redis_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect docmost_redis_data || docker volume create docmost_redis_data
    '';
    partOf = [ "docker-compose-docmost-root.target" ];
    wantedBy = [ "docker-compose-docmost-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-docmost-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
