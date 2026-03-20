{ config, lib, pkgs, ... }:

with lib;
let
  cfg     = config.modules.services.productivity.babybuddy;
  helpers = import ../../lib.nix { inherit lib; };
in
{
  options.modules.services.productivity.babybuddy = {
    enable = mkEnableOption "Baby Buddy - baby and child care tracking";

    serviceName = mkOption {
      type    = types.str;
      default = "Baby Buddy";
    };

    domain = mkOption {
      type    = types.str;
      default = "baby.${config.networking.domain}";
    };

    port = mkOption {
      type    = types.port;
      default = 8110;
    };

    dataDir = mkOption {
      type        = types.str;
      default     = "${config.modules.services.appData.mount}/${config.modules.services.appData.services.${cfg.serviceName}.appID}";
      description = "Data directory. Override to take full control — appData module will not manage this path.";
    };

    secretsFile = mkOption {
      type = types.path;
      default = config.age.secrets.babybuddy-secrets.path;
      description = "Path to environment file containing SECRET_KEY";
    };
  };

  config = mkIf cfg.enable {
    modules.services.appData.services.${cfg.serviceName} = {
      owner = "1000";
      group = "1000";
    };

    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."babybuddy" = {
      image = "lscr.io/linuxserver/babybuddy:latest";
      environmentFiles = [ cfg.secretsFile ];
      environment = {
        TZ = config.time.timeZone;
        PUID = "1000";
        PGID = "1000";
        ALLOWED_HOSTS = cfg.domain;
        CSRF_TRUSTED_ORIGINS = "https://${cfg.domain}";
      };
      volumes = [
        "${cfg.dataDir}/config:/config:rw"
      ];
      ports = [
        "${toString cfg.port}:8000/tcp"
      ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=babybuddy"
        "--network=babybuddy_default"
      ];
    };

    systemd.services."docker-babybuddy" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-babybuddy_default.service" ];
      requires = [ "docker-network-babybuddy_default.service" ];
      partOf = [ "docker-compose-babybuddy-root.target" ];
      wantedBy = [ "docker-compose-babybuddy-root.target" ];
    };

    systemd.services."docker-network-babybuddy_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f babybuddy_default";
      };
      script = ''
        docker network inspect babybuddy_default || docker network create babybuddy_default
      '';
      partOf = [ "docker-compose-babybuddy-root.target" ];
      wantedBy = [ "docker-compose-babybuddy-root.target" ];
    };

    systemd.targets."docker-compose-babybuddy-root" = {
      unitConfig = {
        Description = "Baby Buddy Docker services";
      };
      wantedBy = [ "multi-user.target" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
