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
      default = [ "request.${config.networking.domain}" "requests.${config.networking.domain}" ];
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
    services.seerr = {
      enable = true;
      openFirewall = cfg.openFirewall;
      port = cfg.port;
    };

    # Caddy virtual host (supports multiple domains)
    modules.services.vHosts.hosts.${builtins.head cfg.domains} = {
      reverseProxyPort = cfg.port;
      serverAliases = builtins.tail cfg.domains;
      displayName = "Jellyseerr";
      category = "media";
      icon = "jellyseerr";
    };
  };
}
