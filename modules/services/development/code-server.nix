{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.development.code-server;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  options.modules.services.development.code-server = {
    enable = mkEnableOption "code-server for web-based VS Code development";

    domain = mkOption {
      type = types.str;
      default = "vscode.7co.dev";
      description = "Domain for code-server";
    };

    domainAliases = mkOption {
      type    = types.listOf types.str;
      default = [ ];
      description = "Additional domains served by this virtual host. Each gets a DNS record and Caddy alias.";
    };

    port = mkOption {
      type = types.port;
      default = 11010;
      description = "Port for code-server";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    user = mkOption {
      type = types.str;
      default = "tristonyoder";
      description = "User to run code-server as";
    };

    auth = mkOption {
      type = types.enum [ "password" "none" ];
      default = "none";
      description = "Authentication method (use 'none' with reverse proxy auth)";
    };
  };

  config = mkIf cfg.enable {
    # code-server service (using unstable version)
    services.code-server = {
      enable = true;
      package = pkgs-unstable.code-server;
      host = cfg.host;
      port = cfg.port;
      user = cfg.user;
      auth = cfg.auth;
    };

    # Caddy virtual host for reverse proxy
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyHost = cfg.host;
      reverseProxyPort = cfg.port;
      serverAliases    = cfg.domainAliases;
    };
  };
}
