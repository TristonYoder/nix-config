{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.navidrome;
in
{
  options.modules.services.media.navidrome = {
    enable = mkEnableOption "Navidrome music streaming server";

    domain = mkOption {
      type = types.str;
      default = "navidrome.${config.networking.domain}";
      description = "Domain for Navidrome";
    };

    port = mkOption {
      type = types.port;
      default = 4533;
      description = "Navidrome HTTP port";
    };

    musicDir = mkOption {
      type = types.str;
      default =
        if config.modules.services.media.jellyfin.enable
        then "${config.modules.services.media.jellyfin.mediaDir}/Music"
        else "/data/media/Music";
      description = "Path to the music library";
    };
  };

  config = mkIf cfg.enable {
    services.navidrome = {
      enable = true;
      settings = {
        MusicFolder = cfg.musicDir;
        Port = cfg.port;
        Address = "127.0.0.1";
      };
    };

    # Add navidrome user to media group for shared library access
    users.users.navidrome.extraGroups = [ "media" ];

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
