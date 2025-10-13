{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.productivity.actual;
  
  # Caddy virtual host configuration with Cloudflare DNS TLS
  sharedTlsConfig = ''
    tls {
      dns cloudflare {
        api_token "${builtins.readFile config.age.secrets.cloudflare-api-token.path}"
      }
    }
  '';
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
    # Actual Budget service
    services.actual = {
      enable = true;
      settings.port = cfg.port;
      settings.hostname = "0.0.0.0";
      openFirewall = cfg.openFirewall;
    };

    # Caddy virtual host
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.port}
        ${sharedTlsConfig}
      '';
    };
  };
}

