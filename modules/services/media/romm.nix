{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.romm;
in
{
  options.modules.services.media.romm = {
    enable = mkEnableOption "RomM - ROM manager and game library";

    domain = mkOption {
      type = types.str;
      default = "romm.${config.networking.domain}";
      description = "Domain for RomM";
    };

    port = mkOption {
      type = types.port;
      default = 8095;
      description = "External port for RomM";
    };

    libraryPath = mkOption {
      type = types.str;
      default = "/data/media/Games/Emulation";
      description = "Path to ROM library directory";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/romm";
      description = "Data directory for RomM";
    };

    steamGridDbKeyFile = mkOption {
      type = types.path;
      default = config.age.secrets.romm-steamgriddb-key.path;
      description = "Path to file containing SteamGridDB API key";
    };

    authSecretKeyFile = mkOption {
      type = types.path;
      default = config.age.secrets.romm-auth-secret-key.path;
      description = "Path to file containing ROMM_AUTH_SECRET_KEY";
    };

    dbPasswordFile = mkOption {
      type = types.path;
      default = config.age.secrets.romm-db-password.path;
      description = "Path to file containing MariaDB password";
    };

    steamGridDbKeyFile = mkOption {
      type = types.path;
      default = config.age.secrets.romm-steamgriddb-key.path;
      description = "Path to file containing SteamGridDB API key";
    };

    oidc = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "OIDC authentication for RomM";

          provider = mkOption {
            type = types.str;
            default = "pocket-id";
            description = "OIDC provider name";
          };

          clientId = mkOption {
            type = types.str;
            default = "";
            description = "OIDC client ID";
          };

          clientSecretFile = mkOption {
            type = types.path;
            default = config.age.secrets.romm-oidc-secret.path;
            description = "Path to file containing OIDC client secret";
          };

          redirectUri = mkOption {
            type = types.str;
            default = "https://${cfg.domain}/api/oauth/openid";
            description = "OIDC redirect URI";
          };

          serverApplicationUrl = mkOption {
            type = types.str;
            default = "";
            description = "OIDC issuer/server application URL";
          };

          usernameAttribute = mkOption {
            type = types.str;
            default = "preferred_username";
            description = "OIDC attribute to use as username";
          };
        };
      };
      default = { };
      description = "OIDC authentication configuration";
    };
  };

  config = mkIf cfg.enable {
    # Ensure Docker is enabled
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    # RomM MariaDB container
    virtualisation.oci-containers.containers."romm-db" = {
      image = "mariadb:latest";
      environment = {
        MYSQL_DATABASE = "romm";
        MYSQL_USER = "romm";
      };
      environmentFiles = [
        "/run/romm/db.env"
      ];
      volumes = [
        "${cfg.dataDir}/mysql:/var/lib/mysql:rw"
      ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=romm-db"
        "--network=romm_default"
      ];
    };

    systemd.services."docker-romm-db" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
        ExecStartPre = [
          "+${pkgs.bash}/bin/bash -c '${lib.concatStringsSep " && " [
            "mkdir -p /run/romm"
            "DB_PASS=$(cat ${cfg.dbPasswordFile})"
            "echo \"MYSQL_PASSWORD=$DB_PASS\" > /run/romm/db.env"
            "echo \"MYSQL_ROOT_PASSWORD=$DB_PASS\" >> /run/romm/db.env"
            "chmod 0400 /run/romm/db.env"
          ]}'"
        ];
      };
      after = [ "docker-network-romm_default.service" ];
      requires = [ "docker-network-romm_default.service" ];
      partOf = [ "docker-compose-romm-root.target" ];
      wantedBy = [ "docker-compose-romm-root.target" ];
    };

    # RomM Redis container
    virtualisation.oci-containers.containers."romm-redis" = {
      image = "redis:alpine";
      volumes = [
        "${cfg.dataDir}/redis:/data:rw"
      ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=romm-redis"
        "--network=romm_default"
      ];
    };

    systemd.services."docker-romm-redis" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-romm_default.service" ];
      requires = [ "docker-network-romm_default.service" ];
      partOf = [ "docker-compose-romm-root.target" ];
      wantedBy = [ "docker-compose-romm-root.target" ];
    };

    # RomM main application container
    virtualisation.oci-containers.containers."romm" = {
      image = "rommapp/romm:latest";
      environment = {
        TZ = config.time.timeZone;
        DB_HOST = "romm-db";
        DB_PORT = "3306";
        DB_NAME = "romm";
        DB_USER = "romm";
        REDIS_HOST = "romm-redis";
        REDIS_PORT = "6379";
      } // (optionalAttrs cfg.oidc.enable {
        OIDC_ENABLED = "true";
        OIDC_PROVIDER = cfg.oidc.provider;
        OIDC_CLIENT_ID = cfg.oidc.clientId;
        OIDC_REDIRECT_URI = cfg.oidc.redirectUri;
        OIDC_SERVER_APPLICATION_URL = cfg.oidc.serverApplicationUrl;
        OIDC_USERNAME_ATTRIBUTE = cfg.oidc.usernameAttribute;
      });
      environmentFiles = [
        "/run/romm/romm.env"
      ];
      volumes = [
        "${cfg.libraryPath}:/romm/library:rw"
        "${cfg.dataDir}/assets:/romm/assets:rw"
        "${cfg.dataDir}/config:/romm/config:rw"
        "${cfg.dataDir}/resources:/romm/resources:rw"
        "${cfg.dataDir}/redis_data:/redis-data:rw"
      ];
      ports = [
        "${toString cfg.port}:8080/tcp"
      ];
      dependsOn = [ "romm-db" "romm-redis" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=romm"
        "--network=romm_default"
      ];
    };

    systemd.services."docker-romm" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
        ExecStartPre = [
          "+${pkgs.bash}/bin/bash -c '${lib.concatStringsSep " && " ([
            "mkdir -p /run/romm"
            "mkdir -p ${cfg.dataDir}/{assets,config,resources,redis_data,mysql}"
            "touch ${cfg.dataDir}/config/config.yml"
            "AUTH_KEY=$(cat ${cfg.authSecretKeyFile})"
            "DB_PASS=$(cat ${cfg.dbPasswordFile})"
            "echo \"ROMM_AUTH_SECRET_KEY=$AUTH_KEY\" > /run/romm/romm.env"
            "echo \"DB_PASSWD=$DB_PASS\" >> /run/romm/romm.env"
            "SGDB_KEY=$(cat ${cfg.steamGridDbKeyFile})"
            "echo \"STEAMGRIDDB_API_KEY=$SGDB_KEY\" >> /run/romm/romm.env"
          ] ++ (optionals cfg.oidc.enable [
            "OIDC_SECRET=$(cat ${cfg.oidc.clientSecretFile})"
            "echo \"OIDC_CLIENT_SECRET=$OIDC_SECRET\" >> /run/romm/romm.env"
          ]) ++ [
            "chmod 0400 /run/romm/romm.env"
          ])}'"
        ];
      };
      after = [ "docker-network-romm_default.service" ];
      requires = [ "docker-network-romm_default.service" ];
      partOf = [ "docker-compose-romm-root.target" ];
      wantedBy = [ "docker-compose-romm-root.target" ];
    };

    # Docker network
    systemd.services."docker-network-romm_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f romm_default";
      };
      script = ''
        docker network inspect romm_default || docker network create romm_default
      '';
      partOf = [ "docker-compose-romm-root.target" ];
      wantedBy = [ "docker-compose-romm-root.target" ];
    };

    # Root service target
    systemd.targets."docker-compose-romm-root" = {
      unitConfig = {
        Description = "RomM Docker Compose services";
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Caddy virtual host
    modules.services.vHosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
