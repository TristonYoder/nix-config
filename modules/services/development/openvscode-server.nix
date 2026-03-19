{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.development.openvscode-server;
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  options.modules.services.development.openvscode-server = {
    enable = mkEnableOption "Open VSCode Server for web-based development";

    domain = mkOption {
      type = types.str;
      default = "vscode.7co.dev";
      description = "Domain for Open VSCode Server";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Open VSCode Server";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind to";
    };

    user = mkOption {
      type = types.str;
      default = "tristonyoder";
      description = "User to run Open VSCode Server as";
    };

    withoutConnectionToken = mkOption {
      type = types.bool;
      default = false;
      description = "Disable connection token requirement (use with reverse proxy auth)";
    };
  };

  config = mkIf cfg.enable {
    # Open VSCode Server service (using unstable version)
    services.openvscode-server = {
      enable = true;
      package = pkgs-unstable.openvscode-server;
      host = cfg.host;
      port = cfg.port;
      user = cfg.user;
      withoutConnectionToken = cfg.withoutConnectionToken;
    };

    # Caddy virtual host for reverse proxy
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyHost = cfg.host;
      reverseProxyPort = cfg.port;
    };
  };
}
