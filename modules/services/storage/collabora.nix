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
      default = "collabora.${config.networking.domain}";
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
        # aliasgroup1 is a regex — escape dots so they match literally
        extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
        aliasgroup1 = "https://${lib.strings.replaceStrings ["."] ["\\."] cfg.nextcloudDomain}";
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

    # Configure Nextcloud's richdocuments app to point at this Collabora instance.
    # Runs once after nextcloud-setup; safe to re-run (occ set is idempotent).
    systemd.services.nextcloud-configure-collabora = {
      description = "Configure Nextcloud richdocuments to use Collabora Online";
      after = [ "nextcloud-setup.service" ];
      requires = [ "nextcloud-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "nextcloud";
      };
      script = ''
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set richdocuments wopi_url \
          --value="https://${cfg.domain}"
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set richdocuments disable_certificate_verification \
          --value=""
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set richdocuments wopi_allowlist \
          --value="127.0.0.1"
      '';
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
