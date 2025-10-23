# Auto-generated using compose2nix v0.3.2.
{ pkgs, lib, config, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."postal_mariadb" = {
    image = "mariadb:11.4";
    environment = {
      "MARIADB_ALLOW_EMPTY_ROOT_PASSWORD" = "no";
      "MARIADB_DATABASE" = "postal";
      "MARIADB_ROOT_PASSWORD" = "";
    };
    volumes = [
      "/mariadb:/var/lib/mysql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=[\"healthcheck.sh\", \"--connect\", \"--innodb_initialized\"]"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-start-period=30s"
      "--health-timeout=5s"
      "--network-alias=mariadb"
      "--network=postal_default"
    ];
  };
  systemd.services."docker-postal_mariadb" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "docker-network-postal_default.service"
    ];
    requires = [
      "docker-network-postal_default.service"
    ];
    partOf = [
      "docker-compose-postal-root.target"
    ];
    wantedBy = [
      "docker-compose-postal-root.target"
    ];
  };
  virtualisation.oci-containers.containers."postal_runner" = {
    image = "ghcr.io/postalserver/postal:3.3.3";
    environment = {
      "MAIN_DB_DATABASE" = "postal";
      "MAIN_DB_HOST" = "mariadb";
      "MAIN_DB_PASSWORD" = "";
      "MAIN_DB_PORT" = "3306";
      "MAIN_DB_USERNAME" = "root";
      "MESSAGE_DB_DATABASE" = "postal";
      "MESSAGE_DB_HOST" = "mariadb";
      "MESSAGE_DB_PASSWORD" = "";
      "MESSAGE_DB_PORT" = "3306";
      "MESSAGE_DB_USERNAME" = "root";
      "POSTAL_SIGNING_KEY_PATH" = "/config/signing.key";
      "RAILS_ENVIRONMENT" = "production";
      "RAILS_LOG_TO_STDOUT" = "true";
      "WAIT_FOR_TARGETS" = "mariadb:3306";
      "WAIT_FOR_TIMEOUT" = "60";
    };
    volumes = [
      "/config:/config:ro"
      "/data:/opt/postal/app/data:rw"
    ];
    ports = [
      "25:25/tcp"
      "587:587/tcp"
      "5000:5000/tcp"
    ];
    cmd = [ "/docker-entrypoint.sh" "postal" "web-server" ];
    dependsOn = [
      "postal_mariadb"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=postal"
      "--network=postal_default"
    ];
  };
  systemd.services."docker-postal_runner" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "docker-network-postal_default.service"
    ];
    requires = [
      "docker-network-postal_default.service"
    ];
    partOf = [
      "docker-compose-postal-root.target"
    ];
    wantedBy = [
      "docker-compose-postal-root.target"
    ];
  };
  virtualisation.oci-containers.containers."postal_smtp" = {
    image = "ghcr.io/postalserver/postal:3.3.3";
    environment = {
      "MAIN_DB_DATABASE" = "postal";
      "MAIN_DB_HOST" = "mariadb";
      "MAIN_DB_PASSWORD" = "";
      "MAIN_DB_PORT" = "3306";
      "MAIN_DB_USERNAME" = "root";
      "MESSAGE_DB_DATABASE" = "postal";
      "MESSAGE_DB_HOST" = "mariadb";
      "MESSAGE_DB_PASSWORD" = "";
      "MESSAGE_DB_PORT" = "3306";
      "MESSAGE_DB_USERNAME" = "root";
      "POSTAL_SIGNING_KEY_PATH" = "/config/signing.key";
      "RAILS_ENVIRONMENT" = "production";
      "RAILS_LOG_TO_STDOUT" = "true";
    };
    volumes = [
      "/config:/config:ro"
      "/data:/opt/postal/app/data:rw"
    ];
    cmd = [ "/docker-entrypoint.sh" "postal" "smtp-server" ];
    dependsOn = [
      "postal_mariadb"
      "postal_runner"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=postal-smtp"
      "--network=postal_default"
    ];
  };
  systemd.services."docker-postal_smtp" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "docker-network-postal_default.service"
    ];
    requires = [
      "docker-network-postal_default.service"
    ];
    partOf = [
      "docker-compose-postal-root.target"
    ];
    wantedBy = [
      "docker-compose-postal-root.target"
    ];
  };
  virtualisation.oci-containers.containers."postal_worker" = {
    image = "ghcr.io/postalserver/postal:3.3.3";
    environment = {
      "MAIN_DB_DATABASE" = "postal";
      "MAIN_DB_HOST" = "mariadb";
      "MAIN_DB_PASSWORD" = "";
      "MAIN_DB_PORT" = "3306";
      "MAIN_DB_USERNAME" = "root";
      "MESSAGE_DB_DATABASE" = "postal";
      "MESSAGE_DB_HOST" = "mariadb";
      "MESSAGE_DB_PASSWORD" = "";
      "MESSAGE_DB_PORT" = "3306";
      "MESSAGE_DB_USERNAME" = "root";
      "POSTAL_SIGNING_KEY_PATH" = "/config/signing.key";
      "RAILS_ENVIRONMENT" = "production";
      "RAILS_LOG_TO_STDOUT" = "true";
    };
    volumes = [
      "/config:/config:ro"
      "/data:/opt/postal/app/data:rw"
    ];
    cmd = [ "/docker-entrypoint.sh" "postal" "worker" ];
    dependsOn = [
      "postal_mariadb"
      "postal_runner"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=postal-worker"
      "--network=postal_default"
    ];
  };
  systemd.services."docker-postal_worker" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "docker-network-postal_default.service"
    ];
    requires = [
      "docker-network-postal_default.service"
    ];
    partOf = [
      "docker-compose-postal-root.target"
    ];
    wantedBy = [
      "docker-compose-postal-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-postal_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f postal_default";
    };
    script = ''
      docker network inspect postal_default || docker network create postal_default
    '';
    partOf = [ "docker-compose-postal-root.target" ];
    wantedBy = [ "docker-compose-postal-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-postal-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
