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
  virtualisation.oci-containers.containers."affine_migration_job" = {
    image = "ghcr.io/toeverything/affine:stable";
    environment = {
      "AFFINE_INDEXER_ENABLED" = "false";
      "AFFINE_REVISION" = "stable";
      "CONFIG_LOCATION" = "/data/docker-appdata/affine/config";
      "DATABASE_URL" = "postgresql://affine:{a_secret_was_here}@postgres:5432/affine";
      "DB_DATABASE" = "affine";
      "DB_DATA_LOCATION" = "/data/docker-appdata/affine/postgres/pgdata";
      "DB_PASSWORD" = "{a_secret_was_here}";
      "DB_USERNAME" = "affine";
      "PORT" = "3010";
      "REDIS_SERVER_HOST" = "redis";
      "UPLOAD_LOCATION" = "/data/docker-appdata/affine/storage";
    };
    volumes = [
      "/data/docker-appdata/affine/config:/root/.affine/config:rw"
      "/data/docker-appdata/affine/storage:/root/.affine/storage:rw"
    ];
    cmd = [ "sh" "-c" "node ./scripts/self-host-predeploy.js" ];
    dependsOn = [
      "affine_postgres"
      "affine_redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=affine_migration"
      "--network=affine_default"
    ];
  };
  systemd.services."docker-affine_migration_job" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "no";
    };
    after = [
      "docker-network-affine_default.service"
    ];
    requires = [
      "docker-network-affine_default.service"
    ];
    partOf = [
      "docker-compose-affine-root.target"
    ];
    wantedBy = [
      "docker-compose-affine-root.target"
    ];
  };
  virtualisation.oci-containers.containers."affine_postgres" = {
    image = "pgvector/pgvector:pg16";
    environment = {
      "POSTGRES_DB" = "affine";
      "POSTGRES_HOST_AUTH_METHOD" = "trust";
      "POSTGRES_INITDB_ARGS" = "--data-checksums";
      "POSTGRES_PASSWORD" = "{a_secret_was_here}";
      "POSTGRES_USER" = "affine";
    };
    volumes = [
      "/data/docker-appdata/affine/postgres/pgdata:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"pg_isready\", \"-U\", \"affine\", \"-d\", \"affine\"]"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-timeout=5s"
      "--network-alias=postgres"
      "--network=affine_default"
    ];
  };
  systemd.services."docker-affine_postgres" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-affine_default.service"
    ];
    requires = [
      "docker-network-affine_default.service"
    ];
    partOf = [
      "docker-compose-affine-root.target"
    ];
    wantedBy = [
      "docker-compose-affine-root.target"
    ];
  };
  virtualisation.oci-containers.containers."affine_redis" = {
    image = "redis:7.2-alpine";
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"redis-cli\", \"--raw\", \"incr\", \"ping\"]"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-timeout=5s"
      "--network-alias=redis"
      "--network=affine_default"
    ];
  };
  systemd.services."docker-affine_redis" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-affine_default.service"
    ];
    requires = [
      "docker-network-affine_default.service"
    ];
    partOf = [
      "docker-compose-affine-root.target"
    ];
    wantedBy = [
      "docker-compose-affine-root.target"
    ];
  };
  virtualisation.oci-containers.containers."affine_server" = {
    image = "ghcr.io/toeverything/affine:stable";
    environment = {
      "AFFINE_INDEXER_ENABLED" = "false";
      "AFFINE_REVISION" = "stable";
      "CONFIG_LOCATION" = "/data/docker-appdata/affine/config";
      "DATABASE_URL" = "postgresql://affine:{a_secret_was_here}@postgres:5432/affine";
      "DB_DATABASE" = "affine";
      "DB_DATA_LOCATION" = "/data/docker-appdata/affine/postgres/pgdata";
      "DB_PASSWORD" = "{a_secret_was_here}";
      "DB_USERNAME" = "affine";
      "PORT" = "3010";
      "REDIS_SERVER_HOST" = "redis";
      "UPLOAD_LOCATION" = "/data/docker-appdata/affine/storage";
    };
    volumes = [
      "/data/docker-appdata/affine/config:/root/.affine/config:rw"
      "/data/docker-appdata/affine/storage:/root/.affine/storage:rw"
    ];
    ports = [
      "3010:3010/tcp"
    ];
    dependsOn = [
      "affine_migration_job"
      "affine_postgres"
      "affine_redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=affine"
      "--network=affine_default"
    ];
  };
  systemd.services."docker-affine_server" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-affine_default.service"
    ];
    requires = [
      "docker-network-affine_default.service"
    ];
    partOf = [
      "docker-compose-affine-root.target"
    ];
    wantedBy = [
      "docker-compose-affine-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-affine_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f affine_default";
    };
    script = ''
      docker network inspect affine_default || docker network create affine_default
    '';
    partOf = [ "docker-compose-affine-root.target" ];
    wantedBy = [ "docker-compose-affine-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-affine-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
