{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.collabora;
in
{
  options.modules.services.storage.collabora = {
    enable = mkEnableOption "Collabora Online document server (for Nextcloud Office)";

    domain = mkOption {
      type = types.str;
      default = "office.${config.networking.domain}";
      description = "Domain for Collabora Online";
    };

    port = mkOption {
      type = types.port;
      default = 9980;
      description = "Internal port for Collabora Online";
    };

    nextcloudDomain = mkOption {
      type = types.str;
      default = config.modules.services.storage.nextcloud.domain;
      description = "Nextcloud domain to allow as a WOPI client";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."collabora" = {
      image = "collabora/code:latest";
      environment = {
        # Allow Nextcloud as WOPI host (escaped for regex)
        extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
        aliasgroup1 = "https://${cfg.nextcloudDomain}";
        DONT_GEN_SSL_CERT = "1";
        dictionaries = "en_US";
      };
      ports = [
        "127.0.0.1:${toString cfg.port}:9980/tcp"
      ];
      log-driver = "journald";
      extraOptions = [
        "--cap-add=MKNOD"
        "--network-alias=collabora"
        "--network=collabora_default"
      ];
    };

    systemd.services."docker-collabora" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-collabora_default.service" ];
      requires = [ "docker-network-collabora_default.service" ];
      partOf = [ "docker-compose-collabora-root.target" ];
      wantedBy = [ "docker-compose-collabora-root.target" ];
    };

    systemd.services."docker-network-collabora_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f collabora_default";
      };
      script = ''
        docker network inspect collabora_default || docker network create collabora_default
      '';
      partOf = [ "docker-compose-collabora-root.target" ];
      wantedBy = [ "docker-compose-collabora-root.target" ];
    };

    systemd.targets."docker-compose-collabora-root" = {
      unitConfig.Description = "Collabora Online Docker service";
      wantedBy = [ "multi-user.target" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Collabora Online";
      category = "storage";
      icon = "collabora-online";
      monitor = false;
    };
  };
}
