{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.paperlessNgx;
in
{
  options.modules.services.productivity.paperlessNgx = {
    enable = mkEnableOption "Paperless-ngx document management with OCR";

    domain = mkOption {
      type = types.str;
      default = "paperless.${config.networking.domain}";
      description = "Domain for Paperless-ngx";
    };

    port = mkOption {
      type = types.int;
      default = 28981;
      description = "Port for Paperless-ngx to listen on";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless";
      description = "Directory for Paperless-ngx data";
    };

    mediaDir = mkOption {
      type = types.str;
      default = "/var/lib/paperless/media";
      description = "Directory for Paperless-ngx media files";
    };
  };

  config = mkIf cfg.enable {
    services.paperless = {
      enable = true;
      port = cfg.port;
      address = "127.0.0.1";
      dataDir = cfg.dataDir;
      mediaDir = cfg.mediaDir;
      database.createLocally = true;
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Paperless-ngx";
      category = "productivity";
      icon = "paperless-ngx";
    };
  };
}
