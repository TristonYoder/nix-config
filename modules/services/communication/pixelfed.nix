{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.pixelfed;
in
{
  options.modules.services.communication.pixelfed = {
    enable = mkEnableOption "Pixelfed federated photo sharing";
    
    domain = mkOption {
      type = types.str;
      default = "pixelfed.theyoder.family";
      description = "Domain where Pixelfed web interface is accessible";
    };
    
    federationDomain = mkOption {
      type = types.str;
      default = "theyoder.family";
      description = "Root domain for federation identity (APP_URL)";
    };
    
    nginxPort = mkOption {
      type = types.port;
      default = 8085;
      description = "Port for Pixelfed nginx server (for reverse proxy access)";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/pixelfed";
      description = "Directory for Pixelfed data storage";
    };
    
    secretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing secret environment variables (uses agenix if null)";
    };
    
    automaticMigrations = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to run database migrations automatically";
    };
  };

  config = mkIf cfg.enable {
    # Declare agenix secret for Pixelfed
    age.secrets.pixelfed-env = mkIf (cfg.secretFile == null) {
      file = ../../../secrets/pixelfed-env.age;
      owner = "pixelfed";
      group = "pixelfed";
    };

    # Pixelfed service
    services.pixelfed = {
      enable = true;
      domain = cfg.domain;
      dataDir = cfg.dataDir;
      secretFile = if cfg.secretFile != null then cfg.secretFile else config.age.secrets.pixelfed-env.path;
      
      # Database configuration - use defaults (MySQL, createLocally)
      database.automaticMigrations = cfg.automaticMigrations;
      
      # Configure nginx to listen on custom port (Caddy uses port 80)
      # Bind to all interfaces for Tailscale access from PITS
      nginx.listen = [
        { addr = "0.0.0.0"; port = cfg.nginxPort; }
        { addr = "[::]"; port = cfg.nginxPort; }
      ];
      
      settings = {
        # App Configuration
        APP_NAME = "Pixelfed";
        APP_ENV = "production";
        APP_DEBUG = false;
        APP_URL = "https://${cfg.federationDomain}";  # Federation identity uses root domain
        
        # Redis/Cache/Queue Configuration - use module defaults (Unix socket)
        # The module automatically configures Redis with a Unix socket
        
        # ActivityPub/Federation
        ACTIVITY_PUB = true;
        AP_REMOTE_FOLLOW = true;
        AP_INBOX = true;
        AP_OUTBOX = true;
        AP_SHAREDINBOX = true;
        
        # Instance Configuration  
        INSTANCE_DESCRIPTION = "Pixelfed";
        INSTANCE_PUBLIC_HASHTAGS = true;
        INSTANCE_CONTACT_EMAIL = "admin@theyoder.family";
        INSTANCE_PUBLIC_LOCAL_TIMELINE = true;
        
        # Media Configuration
        MEDIA_EXIF_DATABASE = true;
        IMAGE_QUALITY = "80";
        MAX_PHOTO_SIZE = "15000";  # 15MB
        MAX_ALBUM_LENGTH = "10";
        
        # Registration
        OPEN_REGISTRATION = false;  # Set to true if you want open registration
        ENFORCE_EMAIL_VERIFICATION = true;
        
        # Logging
        LOG_CHANNEL = "stack";
      };
    };

    # Ensure data directory exists with correct permissions  
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 pixelfed pixelfed -"
    ];

    # Caddy reverse proxy to nginx (for local/internal access)
    # Nginx runs on custom port (configured in services.pixelfed.nginx.listen above)
    # Note: External access via PITS goes directly to nginx:8085, this is just for local Caddy access
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.nginxPort}
        import cloudflare_tls
      '';
    };


  };
}

