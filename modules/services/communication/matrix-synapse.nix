{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.matrix-synapse;
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
      default = 8448;
      description = "Client-server and federation API port";
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
    
    appServiceConfigFiles = mkOption {
      type = types.listOf types.path;
      default = [];
      description = "List of application service (bridge) registration files";
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
            # Client-server and federation API
            # Binds to all interfaces for Tailscale access from pits reverse proxy
            # Security: Port is NOT opened in firewall (see networking.firewall section below)
            # Only accessible via Tailscale network or localhost
            # Note: Binding to :: (IPv6) also handles IPv4 on most systems (dual-stack)
            port = cfg.clientPort;
            bind_addresses = [ "::" ];
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
        
        # Application services (bridges)
        app_service_config_files = cfg.appServiceConfigFiles;
        
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
      ensureUsers = [
        {
          name = "matrix-synapse";
        }
      ];
    };

    # Create database with correct collation for Matrix Synapse
    # Matrix requires LC_COLLATE=C for proper operation
    systemd.services.matrix-synapse-init-db = {
      description = "Initialize Matrix Synapse database with correct collation";
      before = [ "matrix-synapse.service" ];
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ config.services.postgresql.package ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        RemainAfterExit = true;
      };
      script = ''
        # Check if database exists
        if ! psql -lqt | cut -d \| -f 1 | grep -qw matrix-synapse; then
          echo "Creating matrix-synapse database with C collation..."
          psql -c "CREATE DATABASE \"matrix-synapse\" LC_COLLATE='C' LC_CTYPE='C' TEMPLATE=template0 OWNER \"matrix-synapse\";"
          echo "Database created successfully"
        else
          echo "Database already exists"
          # Check collation
          COLLATION=$(psql -d matrix-synapse -t -c "SELECT datcollate FROM pg_database WHERE datname='matrix-synapse';" | xargs)
          if [ "$COLLATION" != "C" ]; then
            echo "ERROR: Database exists but has wrong collation: $COLLATION (expected C)"
            echo "Matrix Synapse requires LC_COLLATE=C and LC_CTYPE=C for proper operation."
            echo ""
            echo "To fix this manually:"
            echo "  1. Backup your database: sudo -u postgres pg_dump matrix-synapse > matrix-backup.sql"
            echo "  2. Drop the database: sudo -u postgres psql -c 'DROP DATABASE \"matrix-synapse\";'"
            echo "  3. Recreate with correct collation: sudo -u postgres psql -c 'CREATE DATABASE \"matrix-synapse\" LC_COLLATE=\"C\" LC_CTYPE=\"C\" TEMPLATE=template0 OWNER \"matrix-synapse\";'"
            echo "  4. Restore your data: sudo -u postgres psql matrix-synapse < matrix-backup.sql"
            echo ""
            echo "WARNING: This will prevent Matrix Synapse from starting."
            exit 1
          fi
        fi
      '';
    };

    # Firewall configuration
    # Port is NOT opened in firewall - only accessible via localhost and Tailscale
    # Access from pits reverse proxy happens over Tailscale network
    # No firewall rule needed as Tailscale manages its own firewall rules
    
    # Add restart delays to prevent rapid restart loops and socket conflicts
    systemd.services.matrix-synapse.serviceConfig = {
      RestartSec = "10s";  # Wait 10 seconds before restarting
      StartLimitBurst = 3;  # Only allow 3 restarts
      StartLimitIntervalSec = "5min";  # Within a 5 minute window
    };

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
        import cloudflare_tls
      '';
    };
    
  };
}

