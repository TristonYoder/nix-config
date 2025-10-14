{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.matrix-synapse;
  
  # Caddy virtual host configuration with Cloudflare DNS TLS
  sharedTlsConfig = ''
    tls {
      dns cloudflare {$CLOUDFLARE_API_TOKEN}
    }
  '';
in
{
  options.modules.services.communication.matrix-synapse = {
    enable = mkEnableOption "Matrix Synapse homeserver";
    
    serverName = mkOption {
      type = types.str;
      default = "theyoder.family";
      description = "The domain name of the homeserver (used for user IDs)";
    };
    
    publicBaseUrl = mkOption {
      type = types.str;
      default = "https://matrix.theyoder.family";
      description = "Public URL for the homeserver";
    };
    
    clientPort = mkOption {
      type = types.port;
      default = 8008;
      description = "Client-server API port";
    };
    
    federationPort = mkOption {
      type = types.port;
      default = 8448;
      description = "Federation API port";
    };
    
    enableRegistration = mkOption {
      type = types.bool;
      default = false;
      description = "Allow open registration";
    };
    
    enableUrlPreviews = mkOption {
      type = types.bool;
      default = true;
      description = "Enable URL preview generation";
    };
  };

  config = mkIf cfg.enable {
    # Ensure PostgreSQL is available
    assertions = [
      {
        assertion = config.services.postgresql.enable;
        message = "Matrix Synapse requires PostgreSQL to be enabled";
      }
    ];

    # Matrix Synapse service
    services.matrix-synapse = {
      enable = true;
      
      settings = {
        server_name = cfg.serverName;
        public_baseurl = cfg.publicBaseUrl;
        
        # Listener configuration
        listeners = [
          {
            # Client-server API
            port = cfg.clientPort;
            bind_addresses = [ "127.0.0.1" "::1" ];
            type = "http";
            tls = false;
            x_forwarded = true;
            resources = [
              {
                names = [ "client" "federation" ];
                compress = true;
              }
            ];
          }
        ];
        
        # Database configuration (PostgreSQL)
        database = {
          name = "psycopg2";
          args = {
            database = "matrix-synapse";
            user = "matrix-synapse";
            host = "/run/postgresql";
            cp_min = 5;
            cp_max = 10;
          };
        };
        
        # Registration settings
        enable_registration = cfg.enableRegistration;
        enable_registration_without_verification = false;
        
        # Federation settings
        federation_domain_whitelist = null; # Allow federation with all domains
        
        # URL preview settings
        url_preview_enabled = cfg.enableUrlPreviews;
        url_preview_ip_range_blacklist = [
          "127.0.0.0/8"
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
          "100.64.0.0/10"
          "169.254.0.0/16"
          "::1/128"
          "fe80::/10"
          "fc00::/7"
        ];
        
        # Security settings
        suppress_key_server_warning = true;
        
        # Media store
        media_store_path = "/var/lib/matrix-synapse/media";
        max_upload_size = "50M";
        
        # Logging
        log_config = pkgs.writeText "log_config.yaml" ''
          version: 1
          formatters:
            precise:
              format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
          handlers:
            console:
              class: logging.StreamHandler
              formatter: precise
          loggers:
            synapse:
              level: INFO
          root:
            level: INFO
            handlers: [console]
        '';
      };
      
      # Include registration shared secret from agenix
      extraConfigFiles = [
        config.age.secrets.matrix-registration-secret.path
      ];
    };

    # PostgreSQL database setup
    services.postgresql = {
      ensureDatabases = [ "matrix-synapse" ];
      ensureUsers = [
        {
          name = "matrix-synapse";
          ensureDBOwnership = true;
        }
      ];
    };

    # Firewall configuration - allow access from Tailscale only
    networking.firewall.allowedTCPPorts = mkIf config.modules.services.infrastructure.tailscale.enable [
      cfg.clientPort
      cfg.federationPort
    ];

    # Ensure the media store directory exists
    systemd.tmpfiles.rules = [
      "d /var/lib/matrix-synapse/media 0750 matrix-synapse matrix-synapse -"
    ];

    # Optional: Caddy virtual host if running on same machine
    # Note: For split deployments (david running Synapse, pits running Caddy),
    # configure Caddy in pits/configuration.nix instead
    services.caddy.virtualHosts."matrix.${cfg.serverName}" = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy /_matrix/* http://localhost:${toString cfg.clientPort}
        reverse_proxy /_synapse/client/* http://localhost:${toString cfg.clientPort}
        ${sharedTlsConfig}
      '';
    };
  };
}

