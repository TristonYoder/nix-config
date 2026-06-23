{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.nextcloud;
  pkg = pkgs.nextcloud32;

  builtinApps = listToAttrs (map (name: {
    inherit name;
    value = pkg.packages.apps.${name};
  }) cfg.apps);
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

    enableOfficeApps = mkOption {
      type = types.bool;
      default = true;
      description = "Enable OnlyOffice and Richdocuments office suite integration.";
    };

    enableBackups = mkOption {
      type = types.bool;
      default = true;
      description = "Enable nightly PostgreSQL backups.";
    };
  };

  config = mkIf cfg.enable {
    age.secrets.nextcloud-admin-password = mkIf (cfg.adminPassFile == null) {
      file = ../../../secrets/nextcloud-admin-password.age;
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
        // optionalAttrs cfg.enableOfficeApps {
          inherit (pkg.packages.apps) onlyoffice richdocuments;
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
    # Runs once after PostgreSQL is ready; harmless if versions already match.
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

    # Nextcloud requires direct PHP-FPM access via Caddy rather than a simple reverse proxy
    modules.services.vHosts.hosts.${cfg.domain} = {
      rawConfig = true;
      displayName = "Nextcloud";
      category = "storage";
      icon = "nextcloud";
      extraConfig = ''
        root * ${pkg}

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
  };
}
