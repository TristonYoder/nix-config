# Bitfocus Companion - Control software for Streamdecks and button panels
# Integrates with 2,800+ modules including video switchers, audio, lighting, and automation

{ config, lib, pkgs, ... }:

with lib;
let
  cfg     = config.modules.services.productivity.companion;
  helpers = import ../../lib.nix { inherit lib; };
in
{
  options.modules.services.productivity.companion = {
    enable = mkEnableOption "Bitfocus Companion - Streamdeck control software";

    serviceName = mkOption {
      type        = types.str;
      default     = "companion";
      description = "Service name used for appData volume and vHost domain derivation.";
    };

    domain = mkOption {
      type    = types.str;
      default = "${helpers.toSlug cfg.serviceName}.${config.networking.domain}";
    };

    port = mkOption {
      type    = types.port;
      default = 8880;
    };

    dataDir = mkOption {
      type        = types.str;
      default     = "${config.modules.services.appData.mount}/${config.modules.services.appData.services.${cfg.serviceName}.appID}";
      description = "Data directory. Override to take full control — appData module will not manage this path.";
    };
  };

  config = mkIf cfg.enable {
    modules.services.appData.services.${cfg.serviceName} = {
      owner = "1000";
      group = "1000";
    };

    virtualisation.oci-containers.containers."companion" = {
      image = "ghcr.io/bitfocus/companion/companion:latest";
      volumes = [
        "${cfg.dataDir}:/companion:rw"
      ];
      ports = [
        "${toString cfg.port}:8000/tcp"
        "16622:16622/tcp"
        "28492:28492/tcp"
      ];
      labels = {
        "com.centurylinklabs.watchtower.enable" = "true";
      };
      log-driver = "journald";
      extraOptions = [
        "--network-alias=companion"
        "--network=portainer_default"
      ];
    };

    systemd.services."docker-companion" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-portainer_default.service" ];
      requires = [ "docker-network-portainer_default.service" ];
      partOf = [ "docker-compose-companion-root.target" ];
      wantedBy = [ "docker-compose-companion-root.target" ];
    };

    systemd.targets."docker-compose-companion-root" = {
      unitConfig = {
        Description = "Bitfocus Companion Docker services";
      };
      wantedBy = [ "multi-user.target" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
