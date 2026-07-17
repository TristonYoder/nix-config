{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.miniflux;
in
{
  options.modules.services.productivity.miniflux = {
    enable = mkEnableOption "Miniflux RSS reader";

    domain = mkOption {
      type = types.str;
      default = "miniflux.${config.networking.domain}";
      description = "Domain for Miniflux";
    };

    port = mkOption {
      type = types.int;
      default = 8088;
      description = "Port for Miniflux to listen on";
    };

    adminCredentialsFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to a file containing admin credentials as environment variables.
        Required if CREATE_ADMIN is enabled (the default). The file should
        contain ADMIN_USERNAME and ADMIN_PASSWORD.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.miniflux = {
      enable = true;
      createDatabaseLocally = true;
      adminCredentialsFile = cfg.adminCredentialsFile;
      config = {
        LISTEN_ADDR = "127.0.0.1:${toString cfg.port}";
        BASE_URL = "https://${cfg.domain}";
        CREATE_ADMIN = mkIf (cfg.adminCredentialsFile == null) 0;
      };
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Miniflux";
      category = "productivity";
      icon = "miniflux";
    };
  };
}
