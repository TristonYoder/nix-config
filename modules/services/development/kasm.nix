{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.kasm;
  helpers = import ../../lib.nix { inherit lib; };
in
{
  options.modules.services.development.kasm = {
    enable = mkEnableOption "Kasm Workspaces";

    serviceName = mkOption {
      type = types.str;
      default = "kasm";
      description = "Service name used for appData registration";
    };

    domain = mkOption {
      type = types.str;
      default = "${helpers.toSlug cfg.serviceName}.${config.networking.domain}";
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
      default = "${config.modules.services.appData.mount}/${config.modules.services.appData.services.${cfg.serviceName}.appID}";
      description = "Path for Kasm data storage";
    };
    
    networkSubnet = mkOption {
      type = types.str;
      default = "172.22.0.0/16";
      description = "Docker network subnet for Kasm containers";
    };
    
    
    adminPassword = mkOption {
      type = types.str;
      default = "changeme123";
      description = ''
        Admin password for Kasm web interface.
        Default credentials: admin@kasm.local / (this password)
        IMPORTANT: Change this password after first login!
      '';
    };
    
    userPassword = mkOption {
      type = types.str;
      default = "changeme123";
      description = ''
        Default user password for Kasm.
        Default credentials: user@kasm.local / (this password)
      '';
    };
    
    redisPassword = mkOption {
      type = types.str;
      default = "kasm-redis-local";
      description = ''
        Redis password for Kasm backend (local-only service).
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
        default = "kasm-postgres-local";
        description = ''
          PostgreSQL password for Kasm backend (local-only service).
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
    modules.services.appData.services.${cfg.serviceName} = {
      owner = "root";
      group = "root";
    };

    # Warnings
    warnings = optional (cfg.adminPassword == "changeme123")
      "Kasm admin password is using default value 'changeme123'. Change it after first login or set a custom password in configuration.";
    
    # Enable Kasm Workspaces service
    services.kasmweb = {
      enable = true;
      listenPort = cfg.listenPort;
      listenAddress = cfg.listenAddress;
      datastorePath = cfg.datastorePath;
      networkSubnet = cfg.networkSubnet;
      
      # Passwords - configured via module options
      defaultAdminPassword = cfg.adminPassword;
      defaultUserPassword = cfg.userPassword;
      redisPassword = cfg.redisPassword;
      
      postgres = {
        user = cfg.postgres.user;
        password = cfg.postgres.password;
      };
      
      # SSL configuration (optional)
      sslCertificate = cfg.sslCertificate;
      sslCertificateKey = cfg.sslCertificateKey;
    };
    
    # Ensure Docker is enabled for Kasm containers
    virtualisation.docker.enable = true;
    
    # Open firewall for Kasm
    networking.firewall.allowedTCPPorts = [ cfg.listenPort ];
    
    # Caddy reverse proxy configuration
    modules.services.vHosts.hosts.${cfg.domain} = {
      managedProxy = false;
      extraConfig = ''
        reverse_proxy https://localhost:${toString cfg.listenPort} {
          transport http {
            tls_insecure_skip_verify
          }
          
          # Required headers for Kasm session validation
          header_up Host {upstream_hostport}
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}
          header_up X-Forwarded-Host {host}
        }
      '';
    };
  };
}
