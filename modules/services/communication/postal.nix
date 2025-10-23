{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.postal;
  
  # Generate postal.yml configuration template
  postalConfigTemplate = pkgs.writeText "postal.yml.template" ''
    web_server:
      bind_address: 0.0.0.0
      port: 5000
      max_threads: 5
    
    main_db:
      host: mariadb
      username: root
      password: __POSTAL_DB_PASSWORD__
      database: postal
      encoding: utf8mb4
      pool: 5
    
    message_db:
      host: mariadb
      username: root
      password: __POSTAL_DB_PASSWORD__
      database: postal
      encoding: utf8mb4
      pool: 5
    
    rabbitmq:
      host: 127.0.0.1
      username: postal
      password: postal
      vhost: /postal
    
    web:
      host: ${cfg.hostname}
      protocol: https
    
    smtp_server:
      port: 25
      tls_enabled: true
      tls_certificate_path: ""
      tls_private_key_path: ""
      hostname: ${cfg.smtpHostname}
    
    dns:
      mx_records:
        - ${cfg.smtpHostname}
      smtp_server_hostname: ${cfg.smtpHostname}
      spf_include: ${cfg.smtpHostname}
      return_path_domain: ${cfg.smtpHostname}
      route_domain: ${cfg.smtpHostname}
      track_domain: ${cfg.smtpHostname}
    
    smtp:
      host: 127.0.0.1
      port: 25
      username: ""
      password: ""
    
    rails:
      environment: production
      secret_key_base: __RAILS_SECRET_KEY__
    
    logging:
      enabled: true
      level: info
      
    general:
      use_ip_pools: false
    
    spamd:
      enabled: false
    
    clamav:
      enabled: false
  '';
  
in
{
  options.modules.services.communication.postal = {
    enable = mkEnableOption "Postal mail server";
    
    hostname = mkOption {
      type = types.str;
      default = "postal.7andco.dev";
      description = "Hostname for Postal web interface";
    };
    
    smtpHostname = mkOption {
      type = types.str;
      default = "mail.7andco.dev";
      description = "SMTP hostname for sending mail";
    };
    
    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/postal";
      description = "Base directory for Postal data";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Import docker compose configuration only when enabled
    (import ../../../docker/communication/postal.nix { inherit config lib pkgs; })
    
    # Our customizations
    {
    # Agenix secrets - all secrets managed declaratively
    age.secrets.postal-db-password = {
      file = ../../../secrets/postal-db-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    age.secrets.postal-rails-secret = {
      file = ../../../secrets/postal-rails-secret.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    age.secrets.postal-signing-key = {
      file = ../../../secrets/postal-signing-key.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    age.secrets.postal-admin-password = {
      file = ../../../secrets/postal-admin-password.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    age.secrets.postal-admin-email = {
      file = ../../../secrets/postal-admin-email.age;
      mode = "0400";
      owner = "root";
      group = "root";
    };
    
    # Ensure data directories exist with correct permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/data 0750 root root -"
      "d ${cfg.dataDir}/mariadb 0750 999 999 -"  # MariaDB UID
    ];
    
    # Override the generated container configurations to use proper paths and environment files
    virtualisation.oci-containers.containers."postal_mariadb" = {
      environment = lib.mkForce {
        MARIADB_ALLOW_EMPTY_ROOT_PASSWORD = "no";
        MARIADB_DATABASE = "postal";
        MARIADB_ROOT_PASSWORD = "PLACEHOLDER";  # Will be overridden by environmentFile
      };
      environmentFiles = [
        "${cfg.dataDir}/config/db.env"
      ];
      volumes = lib.mkForce [
        "${cfg.dataDir}/mariadb:/var/lib/mysql:rw"
      ];
    };
    
    virtualisation.oci-containers.containers."postal_runner" = {
      environment = lib.mkForce {
        MAIN_DB_DATABASE = "postal";
        MAIN_DB_HOST = "mariadb";
        MAIN_DB_PASSWORD = "PLACEHOLDER";  # Will be overridden by environmentFile
        MAIN_DB_PORT = "3306";
        MAIN_DB_USERNAME = "root";
        MESSAGE_DB_DATABASE = "postal";
        MESSAGE_DB_HOST = "mariadb";
        MESSAGE_DB_PASSWORD = "PLACEHOLDER";  # Will be overridden by environmentFile
        MESSAGE_DB_PORT = "3306";
        MESSAGE_DB_USERNAME = "root";
        POSTAL_SIGNING_KEY_PATH = "/config/signing.key";
        RAILS_ENVIRONMENT = "production";
        RAILS_LOG_TO_STDOUT = "true";
        WAIT_FOR_TARGETS = "mariadb:3306";
        WAIT_FOR_TIMEOUT = "60";
      };
      environmentFiles = [
        "${cfg.dataDir}/config/db.env"
      ];
      volumes = lib.mkForce [
        "${cfg.dataDir}/config:/config:ro"
        "${cfg.dataDir}/data:/opt/postal/app/data:rw"
      ];
    };
    
    virtualisation.oci-containers.containers."postal_worker" = {
      environment = lib.mkForce {
        MAIN_DB_DATABASE = "postal";
        MAIN_DB_HOST = "mariadb";
        MAIN_DB_PASSWORD = "PLACEHOLDER";  # Will be overridden by environmentFile
        MAIN_DB_PORT = "3306";
        MAIN_DB_USERNAME = "root";
        MESSAGE_DB_DATABASE = "postal";
        MESSAGE_DB_HOST = "mariadb";
        MESSAGE_DB_PASSWORD = "PLACEHOLDER";  # Will be overridden by environmentFile
        MESSAGE_DB_PORT = "3306";
        MESSAGE_DB_USERNAME = "root";
        POSTAL_SIGNING_KEY_PATH = "/config/signing.key";
        RAILS_ENVIRONMENT = "production";
        RAILS_LOG_TO_STDOUT = "true";
      };
      environmentFiles = [
        "${cfg.dataDir}/config/db.env"
      ];
      volumes = lib.mkForce [
        "${cfg.dataDir}/config:/config:ro"
        "${cfg.dataDir}/data:/opt/postal/app/data:rw"
      ];
    };
    
    virtualisation.oci-containers.containers."postal_smtp" = {
      environment = lib.mkForce {
        MAIN_DB_DATABASE = "postal";
        MAIN_DB_HOST = "mariadb";
        MAIN_DB_PASSWORD = "PLACEHOLDER";  # Will be overridden by environmentFile
        MAIN_DB_PORT = "3306";
        MAIN_DB_USERNAME = "root";
        MESSAGE_DB_DATABASE = "postal";
        MESSAGE_DB_HOST = "mariadb";
        MESSAGE_DB_PASSWORD = "PLACEHOLDER";  # Will be overridden by environmentFile
        MESSAGE_DB_PORT = "3306";
        MESSAGE_DB_USERNAME = "root";
        POSTAL_SIGNING_KEY_PATH = "/config/signing.key";
        RAILS_ENVIRONMENT = "production";
        RAILS_LOG_TO_STDOUT = "true";
      };
      environmentFiles = [
        "${cfg.dataDir}/config/db.env"
      ];
      volumes = lib.mkForce [
        "${cfg.dataDir}/config:/config:ro"
        "${cfg.dataDir}/data:/opt/postal/app/data:rw"
      ];
    };
    
    # Copy signing key from agenix secret to config directory
    systemd.services.postal-install-signing-key = {
      description = "Install Postal signing key from secrets";
      wantedBy = [ "multi-user.target" ];
      before = [ "docker-postal_runner.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        echo "Installing Postal signing key..."
        cp ${config.age.secrets.postal-signing-key.path} ${cfg.dataDir}/config/signing.key
        chmod 644 ${cfg.dataDir}/config/signing.key
        echo "Signing key installed"
      '';
    };
    
    # Generate postal.yml configuration with secrets substituted
    systemd.services.postal-generate-config = {
      description = "Generate Postal configuration with secrets";
      wantedBy = [ "multi-user.target" ];
      before = [ "docker-postal_runner.service" ];
      after = [ "postal-install-signing-key.service" ];
      requires = [ "postal-install-signing-key.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        echo "Generating Postal configuration..."
        
        # Load secrets from agenix
        DB_PASSWORD=$(cat ${config.age.secrets.postal-db-password.path})
        RAILS_SECRET=$(cat ${config.age.secrets.postal-rails-secret.path})
        
        # Generate config from template
        ${pkgs.gnused}/bin/sed \
          -e "s|__POSTAL_DB_PASSWORD__|$DB_PASSWORD|g" \
          -e "s|__RAILS_SECRET_KEY__|$RAILS_SECRET|g" \
          ${postalConfigTemplate} > ${cfg.dataDir}/config/postal.yml
        
        chmod 640 ${cfg.dataDir}/config/postal.yml
        echo "Configuration generated successfully"
      '';
    };
    
    # Create environment file for database password
    systemd.services.postal-create-env = {
      description = "Create Postal environment file with database password";
      wantedBy = [ "multi-user.target" ];
      before = [ "docker-postal_mariadb.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        echo "Creating database environment file..."
        DB_PASSWORD=$(cat ${config.age.secrets.postal-db-password.path})
        
        cat > ${cfg.dataDir}/config/db.env <<EOF
MARIADB_ROOT_PASSWORD=$DB_PASSWORD
POSTAL_DB_PASSWORD=$DB_PASSWORD
MAIN_DB_PASSWORD=$DB_PASSWORD
MESSAGE_DB_PASSWORD=$DB_PASSWORD
EOF
        
        chmod 600 ${cfg.dataDir}/config/db.env
        echo "Database environment file created"
      '';
    };
    
    # Initialize database (idempotent)
    systemd.services.postal-initialize-db = {
      description = "Initialize Postal database schema";
      wantedBy = [ "multi-user.target" ];
      after = [ 
        "docker-postal_mariadb.service"
        "docker-postal_runner.service"
        "postal-generate-config.service"
      ];
      requires = [ 
        "docker-postal_mariadb.service"
        "docker-postal_runner.service"
        "postal-generate-config.service"
      ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        # Check if database is already initialized
        if [ -f ${cfg.dataDir}/data/.db-initialized ]; then
          echo "Database already initialized, skipping"
          exit 0
        fi
        
        echo "Waiting for MariaDB to be ready..."
        for i in {1..30}; do
          if ${pkgs.docker}/bin/docker exec postal_mariadb mysqladmin ping -h localhost --silent 2>/dev/null; then
            echo "MariaDB is ready"
            break
          fi
          echo "Waiting for MariaDB... ($i/30)"
          sleep 2
        done
        
        echo "Initializing Postal database schema..."
        ${pkgs.docker}/bin/docker exec postal_runner postal initialize || {
          echo "Failed to initialize database"
          exit 1
        }
        
        # Mark as initialized
        touch ${cfg.dataDir}/data/.db-initialized
        echo "Database initialization complete"
      '';
    };
    
    # Create admin user with credentials from secrets (fully automated)
    systemd.services.postal-create-admin = {
      description = "Create Postal admin user from secrets";
      wantedBy = [ "multi-user.target" ];
      after = [ 
        "postal-initialize-db.service"
        "docker-postal_runner.service"
      ];
      requires = [ 
        "postal-initialize-db.service"
        "docker-postal_runner.service"
      ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        # Check if admin user already created
        if [ -f ${cfg.dataDir}/data/.admin-created ]; then
          echo "Admin user already created, skipping"
          exit 0
        fi
        
        # Wait for Postal to be fully ready
        echo "Waiting for Postal to be ready..."
        sleep 10
        
        # Load admin credentials from secrets
        ADMIN_EMAIL=$(cat ${config.age.secrets.postal-admin-email.path})
        ADMIN_PASSWORD=$(cat ${config.age.secrets.postal-admin-password.path})
        
        echo "Creating Postal admin user..."
        echo "Email: $ADMIN_EMAIL"
        
        # Create admin user using Postal's make-user command with automated input
        ${pkgs.docker}/bin/docker exec postal_runner bash -c "
          postal make-user <<EOF
$ADMIN_EMAIL
$ADMIN_EMAIL
Postal Admin
$ADMIN_PASSWORD
$ADMIN_PASSWORD
y
EOF
        " || {
          echo "Failed to create admin user"
          exit 1
        }
        
        # Mark as created
        touch ${cfg.dataDir}/data/.admin-created
        
        echo ""
        echo "=========================================="
        echo "Postal Admin User Created Successfully"
        echo "=========================================="
        echo "Email:    $ADMIN_EMAIL"
        echo "Password: (stored in agenix secret)"
        echo "Web UI:   https://${cfg.hostname}"
        echo "=========================================="
      '';
    };
    
    # Override docker service dependencies to ensure proper ordering
    systemd.services.docker-postal_runner = {
      after = [
        "postal-install-signing-key.service"
        "postal-generate-config.service"
        "postal-create-env.service"
      ];
      requires = [
        "postal-install-signing-key.service"
        "postal-generate-config.service"
        "postal-create-env.service"
      ];
    };
    
    systemd.services.docker-postal_mariadb = {
      after = [
        "postal-create-env.service"
      ];
      requires = [
        "postal-create-env.service"
      ];
    };
    
    # Open firewall for mail ports
    networking.firewall.allowedTCPPorts = [ 25 587 ];
    }
  ]);
}

