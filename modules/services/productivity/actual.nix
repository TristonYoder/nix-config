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
      default = "budget.${config.networking.domain}";
      description = "Domain for Actual Budget";
    };

    domainAliases = mkOption {
      type    = types.listOf types.str;
      default = [ ];
      description = "Additional domains served by this virtual host. Each gets a DNS record and Caddy alias.";
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
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      serverAliases    = cfg.domainAliases;
    };
  };
}
