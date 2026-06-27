{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.nextcloud;
  pkg = pkgs.nextcloud33;

  builtinApps = listToAttrs (map (name: {
    inherit name;
    value = pkg.packages.apps.${name};
  }) cfg.apps);

  # Escape dots for use in Collabora's aliasgroup regex
  regexEscape = s: lib.strings.replaceStrings [ "." ] [ "\\." ] s;

  # Docker network CIDR allocated to each compose network.
  # Docker assigns these sequentially; keep them in sync if networks change.
  collaboraNetworkCidr = "192.168.32.0/20";
  onlyofficeNetworkCidr = "192.168.48.0/20";
in
{
  options.modules.services.storage.nextcloud = {
    enable = mkEnableOption "Nextcloud file sync and collaboration";

    domain = mkOption {
      type = types.str;
      default = "cloud.${config.networking.domain}";
      description = "Domain for Nextcloud";
    };

    maxUploadSize = mkOption {
      type = types.str;
      default = "16G";
      description = "Maximum file upload size";
    };

    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Nextcloud admin username";
    };

    adminPassFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to admin password file. Defaults to agenix-managed secret.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/nextcloud";
      description = "Nextcloud user data directory";
    };

    apps = mkOption {
      type = types.listOf types.str;
      default = [ "contacts" "calendar" "tasks" "notes" "forms" "tables" "groupfolders" "polls" ];
      description = "Built-in Nextcloud apps to enable. Names must match keys in nextcloud.packages.apps.";
    };

    extraApps = mkOption {
      type = types.attrsOf types.package;
      default = { };
      description = "Additional Nextcloud apps fetched outside of nixpkgs.";
    };

    enableBackups = mkOption {
      type = types.bool;
      default = true;
      description = "Enable nightly PostgreSQL backups.";
    };

    office = {
      collabora = {
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

      onlyoffice = {
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
          description = "Path to file containing the OnlyOffice JWT secret. Defaults to agenix-managed secret.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    age.secrets.nextcloud-admin-password = mkIf (cfg.adminPassFile == null) {
      file = ../../../secrets/nextcloud-admin-password.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };

    age.secrets.nextcloud-onlyoffice-jwt = mkIf (cfg.office.onlyoffice.enable && cfg.office.onlyoffice.jwtSecretFile == null) {
      file = ../../../secrets/nextcloud-onlyoffice-jwt.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };

    services.nextcloud = {
      enable = true;
      hostName = cfg.domain;
      package = pkg;
      database.createLocally = true;
      configureRedis = true;
      maxUploadSize = cfg.maxUploadSize;
      https = true;
      autoUpdateApps.enable = false;
      extraAppsEnable = true;
      extraApps = builtinApps
        // optionalAttrs cfg.office.collabora.enable {
          inherit (pkg.packages.apps) richdocuments;
        }
        // optionalAttrs cfg.office.onlyoffice.enable {
          inherit (pkg.packages.apps) onlyoffice;
        }
        // cfg.extraApps;

      config = {
        dbtype = "pgsql";
        adminuser = cfg.adminUser;
        adminpassFile = if cfg.adminPassFile != null
          then cfg.adminPassFile
          else config.age.secrets.nextcloud-admin-password.path;
        dbname = "nextcloud";
        dbuser = "nextcloud";
        dbhost = "/run/postgresql";
      };

      settings = {
        overwriteProtocol = "https";
        "overwrite.cli.url" = "https://${cfg.domain}";
        default_phone_region = "US";
        trusted_proxies = [ "127.0.0.1" "10.100.0.0/18" "100.64.0.0/10" "fd7a:115c:a1e0::/48" ];
        datadirectory = cfg.dataDir;
      };

      phpOptions."opcache.interned_strings_buffer" = "16";
    };

    # The NixOS nextcloud module unconditionally enables nginx and adds a vhost
    # on port 80. We use Caddy via PHP-FPM instead, so redirect that vhost to a
    # dummy loopback port so nginx doesn't conflict with Caddy.
    services.nginx.virtualHosts.${cfg.domain}.listen = mkForce [
      { addr = "127.0.0.1"; port = 11080; }
    ];

    # Allow Caddy to communicate with PHP-FPM
    services.phpfpm.pools.nextcloud.settings = {
      "listen.owner" = config.services.caddy.user;
      "listen.group" = config.services.caddy.group;
    };
    users.users.caddy.extraGroups = [ "nextcloud" ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 nextcloud nextcloud -"
    ];

    services.postgresqlBackup = mkIf cfg.enableBackups {
      enable = true;
      startAt = "*-*-* 01:15:00";
    };

    # Fix PostgreSQL collation version mismatch after glibc upgrades.
    systemd.services.nextcloud-refresh-collation = {
      description = "Refresh Nextcloud PostgreSQL collation version";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        RemainAfterExit = true;
      };
      script = ''
        ${config.services.postgresql.package}/bin/psql nextcloud \
          -c "ALTER DATABASE nextcloud REFRESH COLLATION VERSION;" \
          2>&1 | grep -v "^$" || true
      '';
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      rawConfig = true;
      displayName = "Nextcloud";
      category = "storage";
      icon = "nextcloud";
      extraConfig = ''
        root * ${config.services.nextcloud.finalPackage}

        php_fastcgi unix//run/phpfpm/nextcloud.sock {
          env front_controller_active true
        }

        file_server
        encode gzip

        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          Referrer-Policy "no-referrer"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "SAMEORIGIN"
          X-XSS-Protection "1; mode=block"
          Permissions-Policy "interest-cohort=()"
        }

        redir /.well-known/carddav /remote.php/dav 301
        redir /.well-known/caldav /remote.php/dav 301
      '';
    };

    # =========================================================================
    # COLLABORA ONLINE
    # =========================================================================

    virtualisation.docker = mkIf (cfg.office.collabora.enable || cfg.office.onlyoffice.enable) {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = mkIf (cfg.office.collabora.enable || cfg.office.onlyoffice.enable)
      (mkDefault "docker");

    virtualisation.oci-containers.containers."collabora" = mkIf cfg.office.collabora.enable {
      image = "collabora/code:latest";
      environment = {
        # aliasgroup1 is a regex — escape dots so they match literally
        extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
        aliasgroup1 = "https://${regexEscape cfg.domain}";
        DONT_GEN_SSL_CERT = "1";
        dictionaries = "en_US";
      };
      ports = [ "127.0.0.1:${toString cfg.office.collabora.port}:9980/tcp" ];
      log-driver = "journald";
      extraOptions = [
        "--cap-add=MKNOD"
        "--network-alias=collabora"
        "--network=collabora_default"
        "--add-host=${cfg.domain}:host-gateway"
      ];
    };

    systemd.services."docker-collabora" = mkIf cfg.office.collabora.enable {
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

    systemd.services."docker-network-collabora_default" = mkIf cfg.office.collabora.enable {
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

    systemd.targets."docker-compose-collabora-root" = mkIf cfg.office.collabora.enable {
      unitConfig.Description = "Collabora Online Docker service";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.nextcloud-configure-collabora = mkIf cfg.office.collabora.enable {
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
          --value="https://${cfg.office.collabora.domain}"
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set richdocuments disable_certificate_verification \
          --value=""
        ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set richdocuments wopi_allowlist \
          --value="127.0.0.1,${collaboraNetworkCidr}"
      '';
    };

    modules.services.vHosts.hosts.${cfg.office.collabora.domain} = mkIf cfg.office.collabora.enable {
      reverseProxyPort = cfg.office.collabora.port;
      displayName = "Collabora Online";
      category = "storage";
      icon = "collabora-online";
      monitor = false;
    };

    # =========================================================================
    # ONLYOFFICE DOCUMENT SERVER
    # =========================================================================

    virtualisation.oci-containers.containers."onlyoffice" = mkIf cfg.office.onlyoffice.enable {
      image = "onlyoffice/documentserver:latest";
      environmentFiles = [
        (if cfg.office.onlyoffice.jwtSecretFile != null
          then cfg.office.onlyoffice.jwtSecretFile
          else config.age.secrets.nextcloud-onlyoffice-jwt.path)
      ];
      environment = {
        JWT_ENABLED = "true";
        JWT_HEADER = "Authorization";
        JWT_IN_BODY = "true";
      };
      ports = [ "127.0.0.1:${toString cfg.office.onlyoffice.port}:80/tcp" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=onlyoffice"
        "--network=onlyoffice_default"
        "--add-host=${cfg.domain}:host-gateway"
      ];
    };

    systemd.services."docker-onlyoffice" = mkIf cfg.office.onlyoffice.enable {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      after = [ "docker-network-onlyoffice_default.service" ];
      requires = [ "docker-network-onlyoffice_default.service" ];
      partOf = [ "docker-compose-onlyoffice-root.target" ];
      wantedBy = [ "docker-compose-onlyoffice-root.target" ];
    };

    systemd.services."docker-network-onlyoffice_default" = mkIf cfg.office.onlyoffice.enable {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "${pkgs.docker}/bin/docker network rm -f onlyoffice_default";
      };
      script = ''
        docker network inspect onlyoffice_default || docker network create onlyoffice_default
      '';
      partOf = [ "docker-compose-onlyoffice-root.target" ];
      wantedBy = [ "docker-compose-onlyoffice-root.target" ];
    };

    systemd.targets."docker-compose-onlyoffice-root" = mkIf cfg.office.onlyoffice.enable {
      unitConfig.Description = "OnlyOffice Document Server Docker service";
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.nextcloud-configure-onlyoffice = mkIf cfg.office.onlyoffice.enable {
      description = "Configure Nextcloud onlyoffice app to use OnlyOffice Document Server";
      after = [ "nextcloud-setup.service" ];
      requires = [ "nextcloud-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "nextcloud";
      };
      script =
        let jwtFile = if cfg.office.onlyoffice.jwtSecretFile != null
              then cfg.office.onlyoffice.jwtSecretFile
              else config.age.secrets.nextcloud-onlyoffice-jwt.path;
        in ''
          JWT_SECRET=$(cat ${jwtFile})
          ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set onlyoffice DocumentServerUrl \
            --value="https://${cfg.office.onlyoffice.domain}/"
          ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set onlyoffice jwt_secret \
            --value="$JWT_SECRET"
          ${config.services.nextcloud.occ}/bin/nextcloud-occ config:app:set onlyoffice jwt_enabled \
            --value="true"
        '';
    };

    modules.services.vHosts.hosts.${cfg.office.onlyoffice.domain} = mkIf cfg.office.onlyoffice.enable {
      reverseProxyPort = cfg.office.onlyoffice.port;
      displayName = "OnlyOffice";
      category = "storage";
      icon = "onlyoffice";
      monitor = false;
    };
  };
}
