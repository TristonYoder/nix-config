{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.kasm;
in
{
  options.modules.services.development.kasm = {
    enable = mkEnableOption "Kasm Workspaces";
    
    domain = mkOption {
      type = types.str;
      default = "kasm.theyoder.family";
      description = "Domain for Kasm Workspaces";
    };
    
    listenPort = mkOption {
      type = types.port;
      default = 5443;
      description = "Port for Kasm web interface";
    };
    
    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address to bind Kasm service";
    };
    
    datastorePath = mkOption {
      type = types.str;
      default = "/data/docker-appdata/kasm";
      description = "Path for Kasm data storage";
    };
    
    networkSubnet = mkOption {
      type = types.str;
      default = "172.20.0.0/16";
      description = "Docker network subnet for Kasm containers";
    };
    
    useAgenixSecrets = mkOption {
      type = types.bool;
      default = true;
      description = "Use agenix-managed secrets for passwords (recommended)";
    };
    
    adminPassword = mkOption {
      type = types.str;
      default = "";
      description = ''
        Admin password (only used if useAgenixSecrets = false).
        When useAgenixSecrets = true, password is read from agenix secret kasm-admin-password.
        Default credentials: admin@kasm.local / (this password)
      '';
    };
    
    userPassword = mkOption {
      type = types.str;
      default = "";
      description = ''
        User password (only used if useAgenixSecrets = false).
        When useAgenixSecrets = true, password is read from agenix secret kasm-user-password.
        Default credentials: user@kasm.local / (this password)
      '';
    };
    
    redisPassword = mkOption {
      type = types.str;
      default = "";
      description = ''
        Redis password (only used if useAgenixSecrets = false).
        When useAgenixSecrets = true, password is read from agenix secret kasm-redis-password.
      '';
    };
    
    postgres = {
      user = mkOption {
        type = types.str;
        default = "kasmapp";
        description = "PostgreSQL user for Kasm";
      };
      
      password = mkOption {
        type = types.str;
        default = "";
        description = ''
          PostgreSQL password (only used if useAgenixSecrets = false).
          When useAgenixSecrets = true, password is read from agenix secret kasm-postgres-password.
        '';
      };
    };
    
    sslCertificate = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to SSL certificate (null to use self-signed)";
    };
    
    sslCertificateKey = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to SSL certificate key (null to use self-signed)";
    };
  };

  config = mkIf cfg.enable {
    # Assertions for secure configuration
    assertions = [
      {
        assertion = cfg.useAgenixSecrets -> (
          config.age.secrets ? kasm-admin-password &&
          config.age.secrets ? kasm-user-password &&
          config.age.secrets ? kasm-redis-password &&
          config.age.secrets ? kasm-postgres-password
        );
        message = "Kasm useAgenixSecrets is enabled but agenix secrets are not configured. Set useAgenixSecrets = false or create the required secrets.";
      }
      {
        assertion = !cfg.useAgenixSecrets -> (
          cfg.adminPassword != "" &&
          cfg.userPassword != "" &&
          cfg.redisPassword != "" &&
          cfg.postgres.password != ""
        );
        message = "Kasm useAgenixSecrets is disabled but passwords are not set. Either enable useAgenixSecrets or provide all passwords.";
      }
    ];
    
    # Warnings for insecure password usage
    warnings = optional (!cfg.useAgenixSecrets)
      "Kasm is configured with plaintext passwords. Consider using useAgenixSecrets = true for better security.";
    
    # Enable Kasm Workspaces service
    services.kasmweb = {
      enable = true;
      listenPort = cfg.listenPort;
      listenAddress = cfg.listenAddress;
      datastorePath = cfg.datastorePath;
      networkSubnet = cfg.networkSubnet;
      
      # Use agenix secrets if enabled, otherwise use provided passwords
      defaultAdminPassword = 
        if cfg.useAgenixSecrets
        then builtins.readFile config.age.secrets.kasm-admin-password.path
        else cfg.adminPassword;
      
      defaultUserPassword = 
        if cfg.useAgenixSecrets
        then builtins.readFile config.age.secrets.kasm-user-password.path
        else cfg.userPassword;
      
      redisPassword = 
        if cfg.useAgenixSecrets
        then builtins.readFile config.age.secrets.kasm-redis-password.path
        else cfg.redisPassword;
      
      postgres = {
        user = cfg.postgres.user;
        password = 
          if cfg.useAgenixSecrets
          then builtins.readFile config.age.secrets.kasm-postgres-password.path
          else cfg.postgres.password;
      };
      
      # SSL configuration (optional)
      sslCertificate = cfg.sslCertificate;
      sslCertificateKey = cfg.sslCertificateKey;
    };
    
    # Ensure Docker is enabled for Kasm containers
    virtualisation.docker.enable = true;
    
    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.datastorePath} 0755 root root -"
    ];
    
    # Open firewall for Kasm
    networking.firewall.allowedTCPPorts = [ cfg.listenPort ];
    
    # Caddy reverse proxy configuration
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy https://localhost:${toString cfg.listenPort} {
          transport http {
            tls_insecure_skip_verify
          }
        }
        import cloudflare_tls
      '';
    };
  };
}

