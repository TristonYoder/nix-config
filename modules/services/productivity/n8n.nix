{ config, lib, pkgs, nixpkgs-unstable, ... }:

with lib;
let
  cfg = config.modules.services.productivity.n8n;
in
{
  options.modules.services.productivity.n8n = {
    enable = mkEnableOption "n8n workflow automation";
    
    domain = mkOption {
      type = types.str;
      default = "n8n.7andco.dev";
      description = "Domain for n8n";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port for n8n";
    };
  };

  config = mkIf cfg.enable {
    # Use n8n from unstable via overlay with unfree allowed
    nixpkgs.overlays = [
      (final: prev: {
        n8n = import nixpkgs-unstable {
          system = prev.system;
          config.allowUnfree = true;
        }.n8n;
      })
    ];

    # n8n service
    services.n8n = {
      enable = true;
      openFirewall = cfg.openFirewall;
      webhookUrl = cfg.domain;
      settings = {
        # Additional n8n settings can go here
      };
    };

    # Caddy virtual host
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:5678
        import cloudflare_tls
      '';
    };
  };
}

