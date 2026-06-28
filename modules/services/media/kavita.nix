{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.kavita;
in
{
  options.modules.services.media.kavita = {
    enable = mkEnableOption "Kavita ebook and comic library server";

    domain = mkOption {
      type = types.str;
      default = "kavita.${config.networking.domain}";
      description = "Domain for Kavita";
    };

    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Port for Kavita to listen on";
    };
  };

  config = mkIf cfg.enable {
    services.kavita = {
      enable = true;
      port = cfg.port;
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Kavita";
      category = "media";
      icon = "kavita";
    };
  };
}
