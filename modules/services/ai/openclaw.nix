{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.openclaw;
in
{
  options.modules.services.ai.openclaw = {
    enable = mkEnableOption "OpenClaw personal AI assistant";

    domain = mkOption {
      type = types.str;
      default = "openclaw.${config.networking.domain}";
      description = "Domain for OpenClaw Web UI and WebSocket gateway";
    };

    gatewayPort = mkOption {
      type = types.port;
      default = 18789;
      description = "WebSocket Gateway port";
    };

    oauthPort = mkOption {
      type = types.port;
      default = 1455;
      description = "OAuth callback port for integrations";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/docker-appdata/openclaw";
      description = "Data directory for configuration and workspace";
    };

    public = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to expose publicly (default: internal only)";
    };

    channels = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "whatsapp" "telegram" "signal" "matrix" ];
      description = "List of messaging channels to enable (configured separately)";
    };
  };

  config = mkIf cfg.enable {
    imports = [ ../../../docker/ai/openclaw.nix ];

    assertions = [
      {
        assertion = config.virtualisation.docker.enable;
        message = "OpenClaw requires Docker to be enabled";
      }
    ];

    # Caddy reverse proxy with WebSocket support
    modules.services.vHosts.${cfg.domain} = {
      reverseProxyPort = cfg.gatewayPort;
      public = cfg.public;
      extraConfig = ''
        reverse_proxy {
          transport http {
            read_timeout 0
            write_timeout 0
          }
        }
      '';
    };
  };
}
