{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.vaultwarden;
  helpers = import ../../lib.nix { inherit lib; };
in
{
  options.modules.services.productivity.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager";

    serviceName = mkOption {
      type = types.str;
      default = "Vaultwarden";
      description = "Service name used for appData registration";
    };

    domain = mkOption {
      type = types.str;
      default = "${helpers.toSlug cfg.serviceName}.${config.networking.domain}";
      description = "Domain for Vaultwarden";
    };
    
    port = mkOption {
      type = types.port;
      default = 8222;
      description = "Vaultwarden port";
    };
    
    backupDir = mkOption {
      type = types.str;
      default = "${config.modules.services.appData.mount}/${config.modules.services.appData.services.${cfg.serviceName}.appID}/backups";
      description = "Backup directory";
    };
    
    adminTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing admin token";
    };
    
    signupDomainsWhitelist = mkOption {
      type = types.str;
      default = "7andco.studio, elizabethallen.photography, ${config.networking.domain}";
      description = "Comma-separated list of allowed signup domains";
    };
  };

  config = mkIf cfg.enable {
    modules.services.appData.services.${cfg.serviceName} = {
      owner = "vaultwarden";
      group = "vaultwarden";
    };

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
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
