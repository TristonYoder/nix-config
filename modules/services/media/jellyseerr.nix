{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.jellyseerr;
in
{
  options.modules.services.media.jellyseerr = {
    enable = mkEnableOption "Jellyseerr media request management";
    
    domains = mkOption {
      type = types.listOf types.str;
      default = [ "request.theyoder.family" "requests.theyoder.family" ];
      description = "Domains for Jellyseerr (space-separated in Caddy config)";
    };
    
    port = mkOption {
      type = types.port;
      default = 5055;
      description = "Jellyseerr port";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall port";
    };
  };

  config = mkIf cfg.enable {
    # Jellyseerr service
    services.jellyseerr = {
      enable = true;
      openFirewall = cfg.openFirewall;
      port = cfg.port;
    };

    # Caddy virtual host (supports multiple domains)
    services.caddy.virtualHosts."${concatStringsSep " " cfg.domains}" = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:${toString cfg.port}
        import cloudflare_tls
      '';
    };
  };
}

