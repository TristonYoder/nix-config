# OpenClaw - Personal AI assistant platform with multi-channel messaging integration
# Provides local AI assistant accessible via WhatsApp, Telegram, Signal, Matrix, Discord, Slack
# Auto-generated Docker compose service configuration
{ config, pkgs, lib, ... }:

let
  domain = "openclaw.${config.networking.domain}";
  gatewayPort = 18789;
  oauthPort = 1455;
  dataDir = "/data/docker-appdata/openclaw";
in
{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Container
  virtualisation.oci-containers.containers."openclaw" = {
    image = "ghcr.io/openclaw/openclaw:latest";

    environmentFiles = [
      config.age.secrets.openclaw-env.path
    ];

    environment = {
      NODE_ENV = "production";
      OPENCLAW_PORT = toString gatewayPort;
      OPENCLAW_DOMAIN = domain;
    };

    volumes = [
      "${dataDir}/config:/home/node/.openclaw/config:rw"
      "${dataDir}/workspace:/home/node/.openclaw/workspace:rw"
      "${dataDir}/data:/home/node/.openclaw:rw"
    ];

    ports = [
      "${toString gatewayPort}:${toString gatewayPort}/tcp"
      "${toString oauthPort}:${toString oauthPort}/tcp"
    ];

    log-driver = "journald";

    extraOptions = [
      "--network-alias=openclaw"
      "--network=openclaw_default"
    ];
  };

  systemd.services."docker-openclaw" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };

    preStart = ''
      mkdir -p ${dataDir}/{config,workspace,data}
      chown -R 1000:1000 ${dataDir}
      chmod -R 755 ${dataDir}
    '';

    after = [ "docker-network-openclaw_default.service" ];
    requires = [ "docker-network-openclaw_default.service" ];
    partOf = [ "docker-compose-openclaw-root.target" ];
    wantedBy = [ "docker-compose-openclaw-root.target" ];
  };

  # Network
  systemd.services."docker-network-openclaw_default" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f openclaw_default";
    };
    script = ''
      docker network inspect openclaw_default || docker network create openclaw_default
    '';
    partOf = [ "docker-compose-openclaw-root.target" ];
    wantedBy = [ "docker-compose-openclaw-root.target" ];
  };

  # Root service
  systemd.targets."docker-compose-openclaw-root" = {
    unitConfig.Description = "OpenClaw AI assistant root target";
    wantedBy = [ "multi-user.target" ];
  };
}
