{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.pocket-id;
in
{
  options.modules.services.infrastructure.pocket-id = {
    enable = mkEnableOption "Pocket ID authentication service";
    
    domain = mkOption {
      type = types.str;
      default = "auth.theyoder.family";
      description = "Domain for Pocket ID";
    };
    
    port = mkOption {
      type = types.port;
      default = 8090;
      description = "Pocket ID port";
    };
    
    trustProxy = mkOption {
      type = types.bool;
      default = true;
      description = "Trust proxy headers for Pocket ID";
    };
  };

  config = mkIf cfg.enable {
    services.pocket-id = {
      enable = true;
      settings = {
        APP_URL = "https://${cfg.domain}";
        TRUST_PROXY = if cfg.trustProxy then "true" else "false";
        PORT = cfg.port;
      };
    };

    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.port}
        import cloudflare_tls
      '';
    };
  };
}
