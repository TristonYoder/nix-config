# AzuraCast - Self-hosted internet radio management (stations, Icecast/Liquidsoap, web player)
# All-in-one image: nginx, PHP, MariaDB, Redis, and the station streaming engines
# all run inside the single "web" container. See:
# https://github.com/AzuraCast/AzuraCast/blob/main/docker-compose.sample.yml
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.azuracast;
in
{
  options.modules.services.media.azuracast = {
    enable = mkEnableOption "AzuraCast internet radio server";

    domain = mkOption {
      type = types.str;
      default = "azuracast.${config.networking.domain}";
      description = "Domain for the AzuraCast admin/station management UI";
    };

    radioDomain = mkOption {
      type = types.str;
      default = "radio.${config.networking.domain}";
      description = "Public-facing domain for the radio player/stream pages (served by the same backend as domain)";
    };

    httpPort = mkOption {
      type = types.port;
      default = 6580;
      description = ''
        Host and container HTTP port. AzuraCast's internal nginx listens on
        this same port (set via AZURACAST_HTTP_PORT), so this is also the
        reverse proxy target for Caddy.
      '';
    };

    sftpPort = mkOption {
      type = types.port;
      default = 2022;
      description = "SFTP port for station file uploads";
    };

    stationPortMin = mkOption {
      type = types.port;
      default = 9500;
      description = ''
        Lower bound of the port range auto-assigned to radio stations
        (Icecast/Shoutcast direct-connect streaming ports). AzuraCast's own
        default range (8000-8496) collides with Jellyfin (8096) on this host,
        so this uses a dedicated range instead.
      '';
    };

    stationPortMax = mkOption {
      type = types.port;
      default = 9599;
      description = ''
        Upper bound of the station port range. 100 ports supports up to ~33
        stations (3 ports each); widen if more are needed.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/azuracast";
      description = "Data directory for AzuraCast (stations, database, uploads, backups)";
    };

    version = mkOption {
      type = types.str;
      default = "latest";
      description = "AzuraCast image tag";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."azuracast" = {
      image = "ghcr.io/azuracast/azuracast:${cfg.version}";
      environment = {
        TZ = config.time.timeZone;
        APPLICATION_ENV = "production";
        AZURACAST_HTTP_PORT = toString cfg.httpPort;
        AZURACAST_SFTP_PORT = toString cfg.sftpPort;
        AUTO_ASSIGN_PORT_MIN = toString cfg.stationPortMin;
        AUTO_ASSIGN_PORT_MAX = toString cfg.stationPortMax;
      };
      volumes = [
        "${cfg.dataDir}/stations:/var/azuracast/stations:rw"
        "${cfg.dataDir}/backups:/var/azuracast/backups:rw"
        "${cfg.dataDir}/db:/var/lib/mysql:rw"
        "${cfg.dataDir}/uploads:/var/azuracast/storage/uploads:rw"
        "${cfg.dataDir}/shoutcast2:/var/azuracast/storage/shoutcast2:rw"
        "${cfg.dataDir}/stereo_tool:/var/azuracast/storage/stereo_tool:rw"
        "${cfg.dataDir}/rsas:/var/azuracast/storage/rsas:rw"
        "${cfg.dataDir}/geoip:/var/azuracast/storage/geoip:rw"
        "${cfg.dataDir}/sftpgo:/var/azuracast/storage/sftpgo:rw"
        "${cfg.dataDir}/acme:/var/azuracast/storage/acme:rw"
      ];
      ports = [
        "${toString cfg.httpPort}:${toString cfg.httpPort}/tcp"
        "${toString cfg.sftpPort}:${toString cfg.sftpPort}/tcp"
      ] ++ map (p: "${toString p}:${toString p}/tcp") (range cfg.stationPortMin cfg.stationPortMax);
      log-driver = "journald";
      extraOptions = [
        "--network-alias=azuracast"
        "--network=azuracast_default"
        "--ulimit=nofile=65536:65536"
      ];
    };

    systemd.services."docker-azuracast" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-azuracast_default.service" ];
      requires = [ "docker-network-azuracast_default.service" ];
      partOf = [ "docker-compose-azuracast-root.target" ];
      wantedBy = [ "docker-compose-azuracast-root.target" ];
    };

    systemd.services."docker-network-azuracast_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f azuracast_default";
      };
      script = ''
        docker network inspect azuracast_default || docker network create azuracast_default
      '';
      partOf = [ "docker-compose-azuracast-root.target" ];
      wantedBy = [ "docker-compose-azuracast-root.target" ];
    };

    systemd.targets."docker-compose-azuracast-root" = {
      unitConfig = {
        Description = "AzuraCast Docker services";
      };
      wantedBy = [ "multi-user.target" ];
    };

    # Same backend serves both the admin UI and the public radio/player pages.
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.httpPort;
      serverAliases = [ cfg.radioDomain ];
      displayName = "AzuraCast";
      category = "media";
      icon = "azuracast";
    };
  };
}
