{ config, lib, pkgs, ... }:

with lib;
let
  nc  = config.modules.services.storage.nextcloud;
  cfg = nc.office.collabora;
  pkg = pkgs.nextcloud33;

  regexEscape = s: lib.strings.replaceStrings [ "." ] [ "\\." ] s;

  # CIDR assigned to the collabora_default docker network.
  # Docker allocates these sequentially; update if the network is recreated
  # with a different subnet.
  networkCidr = "192.168.32.0/20";
in
{
  options.modules.services.storage.nextcloud.office.collabora = {
    enable = mkEnableOption "Collabora Online document server (Nextcloud Office)";

    domain = mkOption {
      type = types.str;
      default = "collabora.${config.networking.domain}";
      description = "Domain for the Collabora Online server";
    };

    port = mkOption {
      type = types.port;
      default = 9980;
      description = "Internal port for Collabora Online";
    };
  };

  config = mkIf (nc.enable && cfg.enable) {
    # Register the richdocuments app via the nextcloud module's internal hook
    modules.services.storage.nextcloud._officeApps = {
      inherit (pkg.packages.apps) richdocuments;
    };

    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = mkDefault "docker";

    virtualisation.oci-containers.containers."collabora" = {
      image = "collabora/code:latest";
      environment = {
        # aliasgroup1 is a regex — escape dots so they match literally
        extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
        aliasgroup1 = "https://${regexEscape nc.domain}";
        DONT_GEN_SSL_CERT = "1";
        dictionaries = "en_US";
      };
      ports = [ "127.0.0.1:${toString cfg.port}:9980/tcp" ];
      log-driver = "journald";
      extraOptions = [
        "--cap-add=MKNOD"
        "--network-alias=collabora"
        "--network=collabora_default"
        "--add-host=${nc.domain}:host-gateway"
      ];
    };

    systemd.services."docker-collabora" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after    = [ "docker-network-collabora_default.service" ];
      requires = [ "docker-network-collabora_default.service" ];
      partOf   = [ "docker-compose-collabora-root.target" ];
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
      partOf   = [ "docker-compose-collabora-root.target" ];
      wantedBy = [ "docker-compose-collabora-root.target" ];
    };

    systemd.targets."docker-compose-collabora-root" = {
      unitConfig.Description = "Collabora Online Docker service";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.nextcloud-configure-collabora = {
      description = "Configure Nextcloud richdocuments to use Collabora Online";
      after    = [ "nextcloud-setup.service" ];
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
          --value="127.0.0.1,${networkCidr}"
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
