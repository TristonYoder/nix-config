{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.tandoor;
in
{
  options.modules.services.productivity.tandoor = {
    enable = mkEnableOption "Tandoor Recipes - Recipe manager and meal planner";

    domain = mkOption {
      type = types.str;
      default = "recipes.${config.networking.domain}";
      description = "Domain for Tandoor";
    };

    port = mkOption {
      type = types.port;
      default = 6780;
      description = "External port for Tandoor";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/tandoor";
      description = "Data directory for Tandoor";
    };

    dbName = mkOption {
      type = types.str;
      default = "djangodb";
      description = "PostgreSQL database name";
    };

    dbUser = mkOption {
      type = types.str;
      default = "djangodb";
      description = "PostgreSQL database user";
    };

    secretsFile = mkOption {
      type = types.path;
      default = config.age.secrets.tandoor-secrets.path;
      description = "Path to environment file containing SECRET_KEY and POSTGRES_PASSWORD";
    };
  };

  config = mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    # Tandoor main container
    virtualisation.oci-containers.containers."tandoor" = {
      image = "vabene1111/recipes";
      environmentFiles = [ cfg.secretsFile ];
      environment = {
        TZ = config.time.timeZone;
        ALLOWED_HOSTS = cfg.domain;
        DB_ENGINE = "django.db.backends.postgresql";
        POSTGRES_DB = cfg.dbName;
        POSTGRES_HOST = "db_tandoor";
        POSTGRES_PORT = "5432";
        POSTGRES_USER = cfg.dbUser;
        GUNICORN_TIMEOUT = "300";
      };
      volumes = [
        "${cfg.dataDir}/mediafiles:/opt/recipes/mediafiles:rw"
        "${cfg.dataDir}/staticfiles:/opt/recipes/staticfiles:rw"
      ];
      ports = [
        "${toString cfg.port}:80/tcp"
      ];
      dependsOn = [ "tandoor-db_tandoor" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=tandoor"
        "--network=tandoor_default"
      ];
    };

    systemd.services."docker-tandoor" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-tandoor_default.service" ];
      requires = [ "docker-network-tandoor_default.service" ];
      partOf = [ "docker-compose-tandoor-root.target" ];
      wantedBy = [ "docker-compose-tandoor-root.target" ];
    };

    # Tandoor database container
    virtualisation.oci-containers.containers."tandoor-db_tandoor" = {
      image = "postgres:16-alpine";
      environmentFiles = [ cfg.secretsFile ];
      environment = {
        DB_ENGINE = "django.db.backends.postgresql";
        POSTGRES_DB = cfg.dbName;
        POSTGRES_HOST = "db_tandoor";
        POSTGRES_PORT = "5432";
        POSTGRES_USER = cfg.dbUser;
      };
      volumes = [
        "${cfg.dataDir}/postgresql:/var/lib/postgresql/data:rw"
      ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=db_tandoor"
        "--network=tandoor_default"
      ];
    };

    systemd.services."docker-tandoor-db_tandoor" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-tandoor_default.service" ];
      requires = [ "docker-network-tandoor_default.service" ];
      partOf = [ "docker-compose-tandoor-root.target" ];
      wantedBy = [ "docker-compose-tandoor-root.target" ];
    };

    # Docker network
    systemd.services."docker-network-tandoor_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f tandoor_default";
      };
      script = ''
        docker network inspect tandoor_default || docker network create tandoor_default
      '';
      partOf = [ "docker-compose-tandoor-root.target" ];
      wantedBy = [ "docker-compose-tandoor-root.target" ];
    };

    # Root service target
    systemd.targets."docker-compose-tandoor-root" = {
      unitConfig = {
        Description = "Tandoor Recipes Docker Compose services";
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Caddy virtual host using new vHosts system
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Tandoor";
      category = "productivity";
      icon = "tandoor-recipes";
    };
  };
}
