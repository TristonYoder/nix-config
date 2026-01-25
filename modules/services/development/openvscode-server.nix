{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.openvscode-server;
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
      type = types.int;
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
    # Open VSCode Server service
    services.openvscode-server = {
      enable = true;
      host = cfg.host;
      port = cfg.port;
      user = cfg.user;
      withoutConnectionToken = cfg.withoutConnectionToken;
    };

    # Caddy virtual host for reverse proxy
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://${cfg.host}:${toString cfg.port}
        import cloudflare_tls
      '';
    };
  };
}
