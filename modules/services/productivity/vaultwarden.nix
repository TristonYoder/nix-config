{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.vaultwarden;
in
{
  options.modules.services.productivity.vaultwarden = {
    enable = mkEnableOption "Vaultwarden password manager";
    
    domain = mkOption {
      type = types.str;
      default = "vault.${config.networking.domain}";
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
      description = ''
        Path to a file containing environment variables for Vaultwarden secrets.
        The file must set ADMIN_TOKEN in the format:
          ADMIN_TOKEN=your-token-here
        This file is passed to systemd as EnvironmentFile and is never read
        at Nix evaluation time — the value never enters the Nix store.
        Recommended: set this to config.age.secrets.vaultwarden-admin-token.path.
      '';
    };
    
    signupDomainsWhitelist = mkOption {
      type = types.str;
      default = "7andco.studio, elizabethallen.photography, ${config.networking.domain}";
      description = "Comma-separated list of allowed signup domains";
    };
  };

  config = mkIf cfg.enable {
    # Vaultwarden service
    services.vaultwarden = {
      enable = true;
      backupDir = cfg.backupDir;
      # Pass secret file via systemd EnvironmentFile — value never enters Nix store.
      # The file must contain: ADMIN_TOKEN=<token>
      environmentFile = cfg.adminTokenFile;
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
        SIGNUPS_DOMAINS_WHITELIST = cfg.signupDomainsWhitelist;
      };
    };

    # Caddy virtual host
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Vaultwarden";
      category = "productivity";
      icon = "vaultwarden";
    };
  };
}
