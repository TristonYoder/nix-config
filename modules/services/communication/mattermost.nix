{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.communication.mattermost;
in
{
  options.modules.services.communication.mattermost = {
    enable = mkEnableOption "Mattermost team communication platform";

    domain = mkOption {
      type = types.str;
      default = "mattermost.${config.networking.domain}";
      description = "Domain for Mattermost";
    };

    siteName = mkOption {
      type = types.str;
      default = "Mattermost";
      description = "Name of the site displayed in the UI";
    };

    port = mkOption {
      type = types.port;
      default = 8065;
      description = "Mattermost listening port";
    };

    mutableConfig = mkOption {
      type = types.bool;
      default = false;
      description = "Allow configuration changes through the web interface";
    };

    enableLocalMode = mkOption {
      type = types.bool;
      default = true;
      description = "Enable local mode socket for mmctl";
    };
  };

  config = mkIf cfg.enable {
    # Ensure PostgreSQL is available
    assertions = [
      {
        assertion = config.services.postgresql.enable;
        message = "Mattermost requires PostgreSQL to be enabled";
      }
    ];

    # Mattermost service
    services.mattermost = {
      enable = true;
      siteName = cfg.siteName;
      siteUrl = "https://${cfg.domain}";
      port = cfg.port;
      mutableConfig = cfg.mutableConfig;
      preferNixConfig = !cfg.mutableConfig;

      # Database configuration (PostgreSQL)
      database = {
        driver = "postgres";
        create = true;
        name = "mattermost";
        user = "mattermost";
        # Use Unix socket authentication
        host = "/run/postgresql";
        socketPath = "/run/postgresql";
      };

      # Enable local mode socket for mmctl administration
      socket = {
        enable = cfg.enableLocalMode;
        path = "/run/mattermost/socket";
        export = true;
      };

      # Additional settings can be configured via services.mattermost.settings
      # or through the web interface if mutableConfig is enabled
      settings = {
        ServiceSettings = {
          # Listen on localhost only, Caddy will handle external access
          ListenAddress = "localhost:${toString cfg.port}";
        };
      };
    };

    # PostgreSQL database setup
    services.postgresql = {
      ensureUsers = [
        {
          name = "mattermost";
        }
      ];
      ensureDatabases = [ "mattermost" ];
    };

    # Caddy virtual host
    modules.services.vHosts."${cfg.domain}" = {
      reverseProxyPort = cfg.port;
    };
  };
}
