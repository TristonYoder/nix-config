{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.linkwarden;
in
{
  options.modules.services.productivity.linkwarden = {
    enable = mkEnableOption "Linkwarden bookmark manager with full-page archiving";

    domain = mkOption {
      type = types.str;
      default = "linkwarden.${config.networking.domain}";
      description = "Domain for Linkwarden";
    };

    port = mkOption {
      type = types.port;
      default = 3333;
      description = "Port for Linkwarden to listen on";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/linkwarden";
      description = "Data directory for Linkwarden storage";
    };

    secretsFile = mkOption {
      type = types.path;
      default = config.age.secrets.linkwarden-env.path;
      description = ''
        Path to environment file containing required secrets.
        Must be created with encrypt-secret.sh before enabling.

        Required variables in the env file:
          DATABASE_URL=postgresql://linkwarden:password@localhost:5432/linkwarden
          NEXTAUTH_SECRET=<random 32+ char string>
      '';
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."linkwarden" = {
      image = "ghcr.io/linkwarden/linkwarden:latest";
      environmentFiles = [ cfg.secretsFile ];
      environment = {
        NEXTAUTH_URL = "https://${cfg.domain}";
        STORAGE_FOLDER = "/data/data";
      };
      volumes = [
        "${cfg.dataDir}/data:/data/data:rw"
      ];
      ports = [
        "127.0.0.1:${toString cfg.port}:3000/tcp"
      ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=linkwarden"
        "--network=linkwarden_default"
      ];
    };

    systemd.services."docker-linkwarden" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-linkwarden_default.service" ];
      requires = [ "docker-network-linkwarden_default.service" ];
      partOf = [ "docker-compose-linkwarden-root.target" ];
      wantedBy = [ "docker-compose-linkwarden-root.target" ];
    };

    systemd.services."docker-network-linkwarden_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f linkwarden_default";
      };
      script = ''
        docker network inspect linkwarden_default || docker network create linkwarden_default
      '';
      partOf = [ "docker-compose-linkwarden-root.target" ];
      wantedBy = [ "docker-compose-linkwarden-root.target" ];
    };

    systemd.targets."docker-compose-linkwarden-root" = {
      unitConfig = {
        Description = "Linkwarden Docker services";
      };
      wantedBy = [ "multi-user.target" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Linkwarden";
      category = "productivity";
      icon = "linkwarden";
    };
  };
}
