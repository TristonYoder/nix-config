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
      default = "oc_";
      description = "Database table prefix for Nextcloud (useful for multiple instances)";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/data/nextcloud";
      description = "Nextcloud data directory for user files";
    };
    
    enableOfficeApps = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Office apps (OnlyOffice, Collabora, etc.)";
    };
    
    enableElementApp = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Element (Matrix) chat app";
    };
    
    # Built-in Nextcloud apps
    enableNews = mkOption {
      type = types.bool;
      default = true;
      description = "Enable News RSS reader";
    };
    
    enableMail = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Mail client";
    };
    
    enableTables = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tables (spreadsheet app)";
    };
    
    enableForms = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Forms";
    };
    
    enableContacts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Contacts";
    };
    
    enableCalendar = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Calendar";
    };
    
    enableGroupfolders = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Groupfolders";
    };
    
    enableExternal = mkOption {
      type = types.bool;
      default = true;
      description = "Enable External storage support";
    };
    
    # Custom apps that need manual fetching
    enableUserSaml = mkOption {
      type = types.bool;
      default = false;
      description = "Enable user_saml SSO authentication";
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
      
      # Office and productivity apps
      extraApps = mkMerge [
        # Built-in Office apps (OnlyOffice, Richdocuments)
        (mkIf cfg.enableOfficeApps (with config.services.nextcloud.package.packages.apps; {
          inherit onlyoffice richdocuments;
        }))
        
        # Built-in core apps
        (mkIf cfg.enableNews (with config.services.nextcloud.package.packages.apps; {
          inherit news;
        }))
        
        (mkIf cfg.enableMail (with config.services.nextcloud.package.packages.apps; {
          inherit mail;
        }))
        
        (mkIf cfg.enableTables (with config.services.nextcloud.package.packages.apps; {
          inherit tables;
        }))
        
        (mkIf cfg.enableForms (with config.services.nextcloud.package.packages.apps; {
          inherit forms;
        }))
        
        (mkIf cfg.enableContacts (with config.services.nextcloud.package.packages.apps; {
          inherit contacts;
        }))
        
        (mkIf cfg.enableCalendar (with config.services.nextcloud.package.packages.apps; {
          inherit calendar;
        }))
        
        (mkIf cfg.enableGroupfolders (with config.services.nextcloud.package.packages.apps; {
          inherit groupfolders;
        }))
        
        (mkIf cfg.enableExternal (with config.services.nextcloud.package.packages.apps; {
          inherit external;
        }))
        
        # Custom apps (manually fetched)
        (mkIf cfg.enableElementApp {
          riotchat = pkgs.fetchNextcloudApp {
            url = "https://github.com/gary-kim/riotchat/releases/download/v0.19.0/riotchat.tar.gz";
            sha256 = "X1yYQUdSTD9jZDX2usmM0cdPRQEe67GOAI3Na3FK224=";
            license = "agpl3Only";
          };
        })
        
        # TODO: Add other custom apps as needed:
        # - user_saml
        # - richdocumentscode
        # - integration_notion
        # - integration_github
        # - officeonline
        # - electronicsignatures
        # - snappymail
        # - libresign
        # - files_readmemd
      ];
      
      # Configuration
      config = {
        dbtype = "pgsql";
        adminuser = cfg.adminUser;
        adminpassFile = if cfg.adminPassFile != null then cfg.adminPassFile else config.age.secrets.nextcloud-admin-password.path;
        # Force installation by setting these required fields
        dbname = "nextcloud";
        dbuser = "nextcloud";
        dbhost = "/run/postgresql";
      };
      
      # Settings
      settings = {
        overwriteProtocol = "https";
        default_phone_region = "US";
        # Trust proxies for reverse proxy chain (localhost + Tailscale ranges)
        trusted_proxies = [ "127.0.0.1" "100.64.0.0/10" "fd7a:115c:a1e0::/48" ];
        # Custom data directory
        datadirectory = cfg.dataDir;
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

    # Create data directory with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 nextcloud nextcloud -"
    ];
    
    # Configure Nextcloud to access user home directories
    # This allows Nextcloud to mount external storage from user directories
    services.nextcloud.extraOptions = {
      # Enable external storage app
      "appstoreenabled" = "true";
    };

    # Disable problematic services until Nextcloud is manually initialized
    systemd.services.nextcloud-setup.enable = false;
    systemd.services.nextcloud-update-db.enable = false;

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

