{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.feishin;
in
{
  options.modules.services.media.feishin = {
    enable = mkEnableOption "Feishin music player web app";

    domain = mkOption {
      type = types.str;
      default = "feishin.${config.networking.domain}";
      description = "Primary domain for Feishin";
    };

    serverAliases = mkOption {
      type = types.listOf types.str;
      default = [ "music.${config.networking.domain}" ];
      description = "Additional domains for Feishin";
    };

    port = mkOption {
      type = types.port;
      default = 9180;
      description = "Feishin port";
    };

    serverName = mkOption {
      type = types.str;
      default = "music.${config.networking.domain}";
      description = "Pre-defined server name";
    };

    serverType = mkOption {
      type = types.str;
      default = "jellyfin";
      description = "Server type: jellyfin, navidrome, or subsonic";
    };

    serverUrl = mkOption {
      type = types.str;
      default = if config.modules.services.media.jellyfin.enable
        then "https://${config.modules.services.media.jellyfin.domain}"
        else "";
      description = "Server URL (http://address:port or https://address:port)";
    };

    remoteUrl = mkOption {
      type = types.str;
      default = if config.modules.services.media.jellyfin.enable
        then "https://${config.modules.services.media.jellyfin.domain}"
        else "";
      description = "Remote URL (http://address or https://address)";
    };

    serverLock = mkOption {
      type = types.bool;
      default = false;
      description = "When true and server name/type/url are set, only username/password can be toggled";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune.enable = true;
    };
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers."feishin" = {
      image = "ghcr.io/jeffvli/feishin:latest";
      environment = {
        SERVER_NAME = cfg.serverName;
        SERVER_LOCK = boolToString cfg.serverLock;
        SERVER_TYPE = cfg.serverType;
        SERVER_URL = cfg.serverUrl;
        REMOTE_URL = cfg.remoteUrl;
        LEGACY_AUTHENTICATION = "false";
        ANALYTICS_DISABLED = "true";
      };
      ports = [
        "127.0.0.1:${toString cfg.port}:9180/tcp"
      ];
      log-driver = "journald";
    };

    systemd.services."docker-feishin" = {
      serviceConfig = {
        Restart = lib.mkOverride 500 "always";
        RestartMaxDelaySec = lib.mkOverride 500 "1m";
        RestartSec = lib.mkOverride 500 "100ms";
        RestartSteps = lib.mkOverride 500 9;
      };
      wantedBy = [ "multi-user.target" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      serverAliases = cfg.serverAliases;
      displayName = "Feishin";
      category = "media";
    };
  };
}
