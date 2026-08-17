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
        Address = "0.0.0.0";
      };
    };

    # Add navidrome user to media group for shared library access
    users.users.navidrome.extraGroups = [ "media" ];

    # The nixpkgs navidrome module bind-mounts MusicFolder read-only into the
    # service's private mount namespace (BindReadOnlyPaths). That bind mount is a
    # snapshot taken at service start — if navidrome starts before the underlying
    # mount for musicDir is up, it captures whatever (empty/stub) directory was
    # there instead, and every track gets scanned as missing. RequiresMountsFor
    # makes systemd order/gate startup on that path actually being mounted first.
    # See CLAUDE.md: "Navidrome Library Wiped After Reboot (BindReadOnlyPaths race)".
    systemd.services.navidrome.unitConfig.RequiresMountsFor = [ cfg.musicDir ];

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Navidrome";
      category = "media";
      icon = "navidrome";
    };
  };
}
