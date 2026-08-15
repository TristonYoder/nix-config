{ config, lib, pkgs, ... }:

with lib;
let
  nc  = config.modules.services.storage.nextcloud;
  cfg = nc.office.onlyoffice;
  pkg = pkgs.nextcloud33;

  jwtFile = if cfg.jwtSecretFile != null
    then cfg.jwtSecretFile
    else config.age.secrets.nextcloud-onlyoffice-jwt.path;
in
{
  options.modules.services.storage.nextcloud.office.onlyoffice = {
    enable = mkEnableOption "OnlyOffice Document Server";

    domain = mkOption {
      type = types.str;
      default = "onlyoffice.${config.networking.domain}";
      description = "Domain for the OnlyOffice Document Server";
    };

    port = mkOption {
      type = types.port;
      default = 9981;
      description = "Internal port for OnlyOffice Document Server";
    };

    jwtSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing the JWT secret shared with OnlyOffice. Defaults to agenix-managed secret.";
    };
  };

  config = mkIf (nc.enable && cfg.enable) {
    age.secrets.nextcloud-onlyoffice-jwt = mkIf (cfg.jwtSecretFile == null) {
      file = ../../../../secrets/nextcloud-onlyoffice-jwt.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };

    # Register the onlyoffice app via the nextcloud module's internal hook
    modules.services.storage.nextcloud._officeApps = {
      inherit (pkg.packages.apps) onlyoffice;
    };

    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = mkDefault "docker";

    virtualisation.oci-containers.containers."onlyoffice" = {
      image = "onlyoffice/documentserver:latest";
      environmentFiles = [ jwtFile ];
      environment = {
        JWT_ENABLED = "true";
        JWT_HEADER = "Authorization";
        JWT_IN_BODY = "true";
      };
      ports = [ "127.0.0.1:${toString cfg.port}:80/tcp" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=onlyoffice"
        "--network=onlyoffice_default"
        "--add-host=${nc.domain}:host-gateway"
      ];
    };

    systemd.services."docker-onlyoffice" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after    = [ "docker-network-onlyoffice_default.service" ];
      requires = [ "docker-network-onlyoffice_default.service" ];
      partOf   = [ "docker-compose-onlyoffice-root.target" ];
      wantedBy = [ "docker-compose-onlyoffice-root.target" ];
    };

    systemd.services."docker-network-onlyoffice_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f onlyoffice_default";
      };
      script = ''
        docker network inspect onlyoffice_default || docker network create onlyoffice_default
      '';
      partOf   = [ "docker-compose-onlyoffice-root.target" ];
      wantedBy = [ "docker-compose-onlyoffice-root.target" ];
    };

    systemd.targets."docker-compose-onlyoffice-root" = {
      unitConfig.Description = "OnlyOffice Document Server Docker service";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.nextcloud-configure-onlyoffice = {
      description = "Configure Nextcloud onlyoffice app to use OnlyOffice Document Server";
      after    = [ "nextcloud-setup.service" ];
      requires = [ "nextcloud-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "nextcloud";
        Restart = "on-failure";
        RestartSec = "10s";
        StartLimitIntervalSec = 0;
      };
      script = ''
        JWT_SECRET=$(cat ${jwtFile})
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set onlyoffice DocumentServerUrl \
          --value="https://${cfg.domain}/"
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set onlyoffice jwt_secret \
          --value="$JWT_SECRET"
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set onlyoffice jwt_enabled \
          --value="true"
      '';
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "OnlyOffice";
      category = "storage";
      icon = "onlyoffice";
      monitor = false;
    };
  };
}
