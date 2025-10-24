{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.nextcloud;
in
{
  options.modules.services.productivity.nextcloud = {
    enable = mkEnableOption "Nextcloud file sharing and collaboration";
    
    domain = mkOption {
      type = types.str;
      default = "cloud.7andco.dev";
      description = "Domain for Nextcloud";
    };
    
    adminUser = mkOption {
      type = types.str;
      default = "TristonYoder";
      description = "Nextcloud admin username";
    };
    
    adminPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing admin password (defaults to agenix secret)";
    };
    
    version = mkOption {
      type = types.str;
      default = "31";
      description = "Nextcloud major version (31, 32, etc.)";
    };
    
    maxUploadSize = mkOption {
      type = types.str;
      default = "16G";
      description = "Maximum file upload size";
    };
    
    trustedDomains = mkOption {
      type = types.listOf types.str;
      default = [
        "cloud.7andco.dev"
        "cloud.theyoder.family"
        "cloud.7andco.studio"
        "10.150.100.30" # Optional LAN IP
      ];
      description = "List of trusted domains";
    };
  };

  config = mkIf cfg.enable {
    # Declare agenix secret for Nextcloud admin password
    age.secrets.nextcloud-admin-password = mkIf (cfg.adminPasswordFile == null) {
      file = ../../../secrets/nextcloud-admin-password.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0400";
    };

    # Nextcloud service
    services.nextcloud = {
      enable = true;
      hostName = cfg.domain;
      # Dynamic version selection based on config
      package = pkgs."nextcloud${cfg.version}";
      # Let NixOS install and configure the database automatically
      database.createLocally = true;
      # Let NixOS install and configure Redis caching automatically
      configureRedis = true;
      # Increase the maximum file upload size
      maxUploadSize = cfg.maxUploadSize;
      # Disable HTTPS since we're using Caddy
      https = false;
      # Enable automatic app updates
      autoUpdateApps.enable = true;
      
      settings = {
        overwriteProtocol = "https";
        default_phone_region = "US";
        trusted_domains = cfg.trustedDomains;
      };
      
      config = {
        dbname = "nextcloud";
        dbhost = "/run/postgresql";
        dbtype = "pgsql";
        adminuser = cfg.adminUser;
        adminpassFile = if cfg.adminPasswordFile != null 
                        then cfg.adminPasswordFile 
                        else config.age.secrets.nextcloud-admin-password.path;
      };
      
      # Suggested by Nextcloud's health check
      phpOptions."opcache.interned_strings_buffer" = "16";
    };

    # Nightly database backups
    services.postgresqlBackup = {
      enable = true;
      startAt = "*-*-* 01:15:00";
    };

    # Create necessary directories and files
    systemd.tmpfiles.rules = [
      "d /var/lib/nextcloud/config 0755 nextcloud nextcloud -"
      "f /var/lib/nextcloud/config/config.php 0640 nextcloud nextcloud -"
    ];

    # Add caddy user to nextcloud group
    users.users.caddy.extraGroups = [ "nextcloud" ];

    # PHP-FPM configuration for Nextcloud
    services.phpfpm.pools.nextcloud = {
      user = "nextcloud";
      group = "nextcloud";
      settings = {
        "listen" = "/run/phpfpm/nextcloud.sock";
        "listen.owner" = "nextcloud";
        "listen.group" = "nextcloud";
        "listen.mode" = "0660";
      };
    };

    # Caddy virtual host configuration
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy / unix//run/phpfpm/nextcloud.sock {
          transport http {
            read_timeout 300s
            write_timeout 300s
          }
        }
        import cloudflare_tls
      '';
    };

    # Redirect aliases to main domain
    services.caddy.virtualHosts."cloud.theyoder.family" = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        redir https://${cfg.domain}{uri} permanent
        import cloudflare_tls
      '';
    };

    services.caddy.virtualHosts."cloud.7andco.studio" = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        redir https://${cfg.domain}{uri} permanent
        import cloudflare_tls
      '';
    };
  };
}

