# Auto-generated using compose2nix v0.1.9.
{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."bazarr" = {
    image = "lscr.io/linuxserver/bazarr:latest";
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Indianapolis";
    };
    volumes = [
      "/data/docker-appdata/bazarr:/config:rw"
      "/data/media/:/data/media:rw"
      "/data/media/Downloads:/data/downloads:rw"
      "/data/media/Movies:/movies:rw"
      "/data/media/TV:/tv:rw"
    ];
    ports = [
      "6767:6767/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=bazarr"
      "--network=media-aq_default"
    ];
  };
  systemd.services."docker-bazarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-media-aq_default.service"
    ];
    requires = [
      "docker-network-media-aq_default.service"
    ];
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."deluge" = {
    image = "lscr.io/linuxserver/deluge:latest";
    environment = {
      DELUGE_LOGLEVEL = "error";
      PGID = "1000";
      PUID = "1000";
      TZ = "Etc/UTC";
    };
    volumes = [
      "/data/docker-appdata/deluge/config/:/config:rw"
      "/data/media/:/data/media:rw"
    ];
    dependsOn = [
      "gluetun"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network=container:gluetun"
    ];
  };
  systemd.services."docker-deluge" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."gluetun" = {
    image = "qmcgaw/gluetun";
    environment = {
      SERVER_CITIES = "Chicago IL";
      VPN_SERVICE_PROVIDER = "mullvad";
      VPN_TYPE = "wireguard";
      WIREGUARD_ADDRESSES = "10.70.74.83/32";
      WIREGUARD_PRIVATE_KEY = "YI61TKW/lwz3C5p3iZUU0yNHNNuFrNKk+35npA1uukc=";
    };
    ports = [
      "9091:9091/tcp"
      "9092:8000/tcp"
      "8112:8112/tcp"
      "6881:6881/tcp"
      "6881:6881/udp"
      "58846:58846/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--network-alias=gluetun"
      "--network=media-aq_default"
    ];
  };
  systemd.services."docker-gluetun" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-media-aq_default.service"
    ];
    requires = [
      "docker-network-media-aq_default.service"
    ];
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."lidarr" = {
    image = "lscr.io/linuxserver/lidarr:latest";
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Indianapolis";
    };
    volumes = [
      "/data/docker-appdata/lidar:/config:rw"
      "/data/media/:/data/media:rw"
      "/data/media/Downloads:/data/downloads:rw"
      "/data/media/Music:/music:rw"
    ];
    ports = [
      "8686:8686/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=lidarr"
      "--network=media-aq_default"
    ];
  };
  systemd.services."docker-lidarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-media-aq_default.service"
    ];
    requires = [
      "docker-network-media-aq_default.service"
    ];
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."prowlarr" = {
    image = "lscr.io/linuxserver/prowlarr:latest";
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Indianapolis";
    };
    volumes = [
      "/data/docker-appdata/prowlarr:/config:rw"
    ];
    ports = [
      "9696:9696/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=prowlarr"
      "--network=media-aq_default"
    ];
  };
  systemd.services."docker-prowlarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-media-aq_default.service"
    ];
    requires = [
      "docker-network-media-aq_default.service"
    ];
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."radarr" = {
    image = "ghcr.io/linuxserver/radarr";
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Indianapolis";
      UMASK_SET = "022";
    };
    volumes = [
      "/data/docker-appdata/radarr:/config:rw"
      "/data/media/:/data/media:rw"
      "/data/media/Downloads:/data/downloads:rw"
      "/data/media/Movies:/movies:rw"
    ];
    ports = [
      "7878:7878/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=radarr"
      "--network=media-aq_default"
    ];
  };
  systemd.services."docker-radarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-media-aq_default.service"
    ];
    requires = [
      "docker-network-media-aq_default.service"
    ];
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."readarr" = {
    image = "lscr.io/linuxserver/readarr:develop";
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Indianapolis";
    };
    volumes = [
      "/data/docker-appdata/readarr:/config:rw"
      "/data/media/:/data/media:rw"
      "/data/media/Books:/books:rw"
      "/data/media/Downloads:/data/downloads:rw"
    ];
    ports = [
      "8787:8787/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=readarr"
      "--network=media-aq_default"
    ];
  };
  systemd.services."docker-readarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-media-aq_default.service"
    ];
    requires = [
      "docker-network-media-aq_default.service"
    ];
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."sonarr" = {
    image = "ghcr.io/linuxserver/sonarr";
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Indianapolis";
      UMASK_SET = "022";
    };
    volumes = [
      "/data/docker-appdata/sonarr:/config:rw"
      "/data/media/:/data/media:rw"
      "/data/media/Downloads:/data/downloads:rw"
      "/data/media/TV:/tv:rw"
    ];
    ports = [
      "8989:8989/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=sonarr"
      "--network=media-aq_default"
    ];
  };
  systemd.services."docker-sonarr" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    after = [
      "docker-network-media-aq_default.service"
    ];
    requires = [
      "docker-network-media-aq_default.service"
    ];
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };
  virtualisation.oci-containers.containers."transmission" = {
    image = "lscr.io/linuxserver/transmission:latest";
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "Etc/UTC";
    };
    volumes = [
      "/data/docker-appdata/transmission/config/:/config:rw"
      "/data/media/:/data/media:rw"
      "/data/media/Downloads/:/downloads:rw"
    ];
    dependsOn = [
      "gluetun"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network=container:gluetun"
    ];
  };
  systemd.services."docker-transmission" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
      RestartMaxDelaySec = lib.mkOverride 500 "1m";
      RestartSec = lib.mkOverride 500 "100ms";
      RestartSteps = lib.mkOverride 500 9;
    };
    partOf = [
      "docker-compose-media-aq-root.target"
    ];
    wantedBy = [
      "docker-compose-media-aq-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-media-aq_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.docker}/bin/docker network rm -f media-aq_default";
    };
    script = ''
      docker network inspect media-aq_default || docker network create media-aq_default
    '';
    partOf = [ "docker-compose-media-aq-root.target" ];
    wantedBy = [ "docker-compose-media-aq-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-media-aq-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
