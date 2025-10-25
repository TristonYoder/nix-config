{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.nextcloud;
in
{
  options.modules.services.storage.nextcloud = {
    enable = mkEnableOption "Nextcloud file synchronization and collaboration";
    
    domain = mkOption {
      type = types.str;
      default = "cloud.7andco.dev";
      description = "Domain for Nextcloud web interface";
    };
    
    package = mkOption {
      type = types.package;
      default = pkgs.nextcloud31;
      description = "Nextcloud package version";
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
      description = "Path to file containing admin password (uses agenix if null)";
    };
    
    autoUpdateApps = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic app updates";
    };
    
    enableBackups = mkOption {
      type = types.bool;
      default = true;
      description = "Enable nightly PostgreSQL backups";
    };
    
    dbTablePrefix = mkOption {
      type = types.str;
      default = "nc1_";
      description = "Database table prefix for Nextcloud (useful for multiple instances)";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/data/nextcloud";
      description = "Nextcloud data directory for user files";
    };
  };

  config = mkIf cfg.enable {
    # Declare agenix secret for Nextcloud admin password
    age.secrets.nextcloud-admin-password = mkIf (cfg.adminPassFile == null) {
      file = ../../../secrets/nextcloud-admin-password.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };

    # Ensure PostgreSQL is available
    assertions = [
      {
        assertion = config.services.postgresql.enable;
        message = "Nextcloud requires PostgreSQL to be enabled";
      }
    ];

    # Nextcloud service configuration
    services.nextcloud = {
      enable = true;
      hostName = cfg.domain;
      package = cfg.package;
      dataDir = cfg.dataDir;
      
      # Database configuration - PostgreSQL
      database.createLocally = true;
      
      # Redis caching
      configureRedis = true;
      
      # Upload size
      maxUploadSize = cfg.maxUploadSize;
      
      # HTTPS
      https = true;
      
      # App updates
      autoUpdateApps.enable = cfg.autoUpdateApps;
      extraAppsEnable = true;
      
      # Configuration
      config = {
        dbtype = "pgsql";
        adminuser = cfg.adminUser;
        adminpassFile = if cfg.adminPassFile != null then cfg.adminPassFile else config.age.secrets.nextcloud-admin-password.path;
        dbtableprefix = cfg.dbTablePrefix;
      };
      
      # Settings
      settings = {
        overwriteProtocol = "https";
        default_phone_region = "US";
        # Trust proxies for reverse proxy chain (localhost + Tailscale ranges)
        trusted_proxies = [ "127.0.0.1" "100.64.0.0/10" "fd7a:115c:a1e0::/48" ];
      };
      
      # PHP optimization (suggested by Nextcloud health check)
      phpOptions."opcache.interned_strings_buffer" = "16";
    };

    # Configure PHP-FPM for Caddy
    # Set socket ownership to caddy user/group so Caddy can communicate with PHP-FPM
    services.phpfpm.pools.nextcloud.settings = {
      "listen.owner" = config.services.caddy.user;
      "listen.group" = config.services.caddy.group;
    };

    # Add caddy user to nextcloud group for proper permissions
    users.users.caddy.extraGroups = [ "nextcloud" ];

    # PostgreSQL backups
    services.postgresqlBackup = mkIf cfg.enableBackups {
      enable = true;
      startAt = "*-*-* 01:15:00";
    };

    # Caddy virtual host on David
    # Caddy serves Nextcloud directly via PHP-FPM Unix socket
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        # Serve Nextcloud via PHP-FPM
        root * ${config.services.nextcloud.package}
        
        # PHP FastCGI through Unix socket
        php_fastcgi unix//run/phpfpm/nextcloud.sock {
          env front_controller_active true
        }
        
        # File server
        file_server
        
        # Compression
        encode gzip
        
        # Security headers
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          Referrer-Policy "no-referrer"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "SAMEORIGIN"
          X-XSS-Protection "1; mode=block"
          Permissions-Policy "interest-cohort=()"
        }
        
        # Redirect CalDAV/CardDAV well-known endpoints
        redir /.well-known/carddav /remote.php/dav 301
        redir /.well-known/caldav /remote.php/dav 301
        
        # Cloudflare TLS with DNS-01 challenge
        import cloudflare_tls
      '';
    };
  };
}

