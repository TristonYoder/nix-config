{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.vaultwarden;
  
  # Helper function for Caddy virtual host with Cloudflare TLS
  cloudflareApiToken = 
    if config.age.secrets ? cloudflare-api-token
    then builtins.readFile config.age.secrets.cloudflare-api-token.path
    else "mDB6U0PcLl-QtjAlX5gskVgH4UO7_QMo5eLY0POq";  # Fallback during migration
  
  sharedTlsConfig = ''
    tls {
      dns cloudflare {
        api_token "${cloudflareApiToken}"
      }
    }
  '';
in
{
  options.modules.services.productivity.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager";
    
    domain = mkOption {
      type = types.str;
      default = "vault.theyoder.family";
      description = "Domain for Vaultwarden";
    };
    
    port = mkOption {
      type = types.port;
      default = 8222;
      description = "Vaultwarden port";
    };
    
    backupDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/vaultwarden/backups";
      description = "Backup directory";
    };
    
    adminTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing admin token";
    };
    
    signupDomainsWhitelist = mkOption {
      type = types.str;
      default = "7andco.studio, elizabehthallen.photography, theyoder.family";
      description = "Comma-separated list of allowed signup domains";
    };
  };

  config = mkIf cfg.enable {
    # Vaultwarden service
    services.vaultwarden = {
      enable = true;
      backupDir = cfg.backupDir;
      config = {
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = cfg.port;
        DOMAIN = "https://${cfg.domain}";
        ENABLE_WEBSOCKET = "true";
        SIGNUPS_ALLOWED = "false";
        SIGNUPS_VERIFY = "false";
        SENDS_ALLOWED = "true";
        INVITATIONS_ALLOWED = "true";
        INVITATION_ORG_NAME = "7 & Co. Vaultwarden";
        ADMIN_TOKEN = 
          if cfg.adminTokenFile != null
          then builtins.readFile cfg.adminTokenFile
          else "supersecretadmintoken";  # Fallback during migration
        SIGNUPS_DOMAINS_WHITELIST = cfg.signupDomainsWhitelist;
      };
    };

    # Caddy virtual host
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.port}
        ${sharedTlsConfig}
      '';
    };
  };
}

