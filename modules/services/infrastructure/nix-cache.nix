{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.nix-cache;
in
{
  options.modules.services.infrastructure.nix-cache = {
    enable = mkEnableOption "Nix binary cache server (Harmonia)";

    domain = mkOption {
      type = types.str;
      default = "cache.${config.networking.domain}";
      description = "Domain for the binary cache";
    };

    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Port for Harmonia to listen on";
    };

    signingKeyFile = mkOption {
      type = types.path;
      default = config.age.secrets.nix-cache-signing-key.path;
      description = "Path to the Nix binary cache signing private key";
    };
  };

  config = mkIf cfg.enable {
    services.harmonia = {
      enable = true;
      signKeyPaths = [ cfg.signingKeyFile ];
      settings = {
        bind = "[::]:${toString cfg.port}";
      };
    };

    # Reverse proxy via Caddy (internal only)
    modules.services.vHosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      public = false;
    };
  };
}
