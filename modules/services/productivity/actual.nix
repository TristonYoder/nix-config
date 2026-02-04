{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.productivity.actual;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  options.modules.services.productivity.actual = {
    enable = mkEnableOption "Actual Budget";

    domain = mkOption {
      type = types.str;
      default = "budget.theyoder.family";
      description = "Domain for Actual Budget";
    };

    port = mkOption {
      type = types.port;
      default = 1111;
      description = "Actual Budget port";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port";
    };
  };

  config = mkIf cfg.enable {
    # Actual Budget service (using unstable version)
    services.actual = {
      enable = true;
      package = pkgs-unstable.actual-server;
      settings.port = cfg.port;
      settings.hostname = "0.0.0.0";
      openFirewall = cfg.openFirewall;
    };

    # Caddy virtual host
    modules.services.vHosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
