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
      default = 23000;
      description = ''
        Lower bound of the port range auto-assigned to radio stations
        (Icecast/Shoutcast direct-connect streaming ports). AzuraCast's own
        default range (8000-8496) collides with Jellyfin (8096) on this host.
        23000-24999 sits in a large confirmed-empty gap on david (nothing
        bound between 22000 and 28492 per `ss -tulpn`), well clear of every
        other service's port range instead of just squeezed next to them.
      '';
    };

    stationPortMax = mkOption {
      type = types.port;
      default = 24999;
      description = ''
        Upper bound of the station port range. AzuraCast reserves a full
        10-port block per station (frontend/telnet/dj/headroom), not just the
        3 ports actually bound - confirmed empirically when 10 stations
        exhausted the previous 100-port range. 2000 ports here supports 200
        stations. Widen further only after checking `ss -tulpn` for occupied
        ports first - don't just round up blindly.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/azuracast";
      description = "Data directory for AzuraCast (stations, database, uploads, backups)";
    };

    mediaDir = mkOption {
      type = types.str;
      default = "/data/media";
      description = "Root shared media directory (matches modules.services.media.jellyfin.mediaDir)";
    };

    libraryMounts = mkOption {
      type = types.listOf types.str;
      default = [ "Music" "Podcasts" "Audiobooks" ];
      description = ''
        Subdirectories of mediaDir to mount read-only into the container so
        they can be added as AzuraCast Storage Locations, or referenced
        directly by a station's remote_url playlists (Liquidsoap's playlist()
        source, which reads local paths without going through AzuraCast's own
        media library/scan queue at all). Read-only because AzuraCast's media
        manager can rename/tag/reorganize files it can write to, which would
        fight with beets/Jellyfin's management of the same library.

        Mounted at the *same absolute path* inside the container as on the
        host, so that m3u files elsewhere in the library (which reference
        tracks by their host path, e.g. Plexamp/Jellyfin-generated playlists)
        resolve correctly without any path rewriting.

        After first login, add a Storage Location (Administration >
        Storage Locations) pointing at the container path for each library
        you want a station to use, then assign it as that station's Media
        storage location.
      '';
    };

    version = mkOption {
      type = types.str;
      default = "latest";
      description = "AzuraCast image tag";
    };

    puid = mkOption {
      type = types.int;
      default = 1000;
      description = "UID the container's internal azuracast user runs as (also used to pre-own bind-mounted data dirs)";
    };

    pgid = mkOption {
      type = types.int;
      default = 1000;
      description = "GID the container's internal azuracast user runs as (also used to pre-own bind-mounted data dirs)";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    # AzuraCast's own startup scripts chown /var/azuracast/storage/* to the
    # azuracast user on every boot, but NOT /var/azuracast/stations or
    # /var/azuracast/backups. Left to Docker's default bind-mount behavior
    # those two would be created as root and the app (running as puid/pgid)
    # can't write to them, so pre-create and own them ourselves.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}/stations 0755 ${toString cfg.puid} ${toString cfg.pgid} -"
      "d ${cfg.dataDir}/backups 0755 ${toString cfg.puid} ${toString cfg.pgid} -"
    ];

    virtualisation.oci-containers.containers."azuracast" = {
      image = "ghcr.io/azuracast/azuracast:${cfg.version}";
      environment = {
        TZ = config.time.timeZone;
        APPLICATION_ENV = "production";
        AZURACAST_HTTP_PORT = toString cfg.httpPort;
        AZURACAST_SFTP_PORT = toString cfg.sftpPort;
        AUTO_ASSIGN_PORT_MIN = toString cfg.stationPortMin;
        AUTO_ASSIGN_PORT_MAX = toString cfg.stationPortMax;
        # Required for first-boot DB init (upstream mariadb entrypoint aborts
        # without one of the MYSQL_*_PASSWORD vars). The DB isn't reachable
        # outside the container, so a random root password is fine.
        MYSQL_RANDOM_ROOT_PASSWORD = "yes";
        PUID = toString cfg.puid;
        PGID = toString cfg.pgid;
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
      ] ++ map (name: "${cfg.mediaDir}/${name}:${cfg.mediaDir}/${name}:ro") cfg.libraryMounts;
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
