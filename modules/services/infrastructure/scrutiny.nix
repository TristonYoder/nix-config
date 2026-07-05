{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.scrutiny;
in
{
  options.modules.services.infrastructure.scrutiny = {
    enable = mkEnableOption "Scrutiny S.M.A.R.T. disk health monitoring";

    domain = mkOption {
      type = types.str;
      default = "scrutiny.${config.networking.domain}";
      description = "Domain for Scrutiny";
    };

    port = mkOption {
      type = types.int;
      default = 8085;
      description = "Port for Scrutiny to listen on";
    };
  };

  config = mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      settings.web.listen = {
        port = cfg.port;
        host = "127.0.0.1";
      };
      collector.enable = true;
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Scrutiny";
      category = "infrastructure";
      icon = "scrutiny";
      monitor = true;
    };
  };
}
