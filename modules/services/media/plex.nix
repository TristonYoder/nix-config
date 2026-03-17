{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.plex;
in
{
  options.modules.services.media.plex = {
    enable = mkEnableOption "Plex media server";

    domain = mkOption {
      type = types.str;
      default = "plex.${config.networking.domain}";
      description = "Domain for Plex";
    };

    port = mkOption {
      type = types.port;
      default = 32400;
      description = "Plex port (service listens on 32400; this only affects reverse proxy settings)";
    };

    plexPass = mkOption {
      type = types.bool;
      default = false;
      description = "Use Plex Pass package when available";
    };

    package = mkOption {
      type = types.package;
      default = if cfg.plexPass then (pkgs.plexpass or pkgs.plex) else pkgs.plex;
      description = "Plex package to use";
    };

    user = mkOption {
      type = types.str;
      default = "plex";
      description = "User account for Plex";
    };

    group = mkOption {
      type = types.str;
      default = "plex";
      description = "Group for Plex";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/plex";
      description = "Plex data directory";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Plex";
    };

    extraScanners = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional Plex scanners";
    };

    extraPlugins = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional Plex plugins";
    };

    accelerationDevices = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Device paths for Plex hardware acceleration";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.port == 32400;
        message = "modules.services.media.plex.port must be 32400 (Plex listens on a fixed port).";
      }
    ];
    services.plex = {
      enable = true;
      user = cfg.user;
      group = cfg.group;
      package = cfg.package;
      dataDir = cfg.dataDir;
      openFirewall = cfg.openFirewall;
      extraScanners = cfg.extraScanners;
      extraPlugins = cfg.extraPlugins;
      accelerationDevices = cfg.accelerationDevices;
    };

    # Ensure media group exists and plex user has access
    users.groups.media = { };
    users.users.plex.extraGroups = [ "media" "video" "render" ];

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
