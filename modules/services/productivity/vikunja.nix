{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.vikunja;
in
{
  options.modules.services.productivity.vikunja = {
    enable = mkEnableOption "Vikunja task and project management";

    domain = mkOption {
      type = types.str;
      default = "vikunja.${config.networking.domain}";
      description = "Domain for Vikunja";
    };

    port = mkOption {
      type = types.int;
      default = 3456;
      description = "Port for Vikunja to listen on";
    };
  };

  config = mkIf cfg.enable {
    services.vikunja = {
      enable = true;
      port = cfg.port;
      frontendScheme = "https";
      frontendHostname = cfg.domain;
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Vikunja";
      category = "productivity";
      icon = "vikunja";
    };
  };
}
