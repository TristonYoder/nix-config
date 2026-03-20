{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.open-webui;
  helpers = import ../../lib.nix { inherit lib; };
in
{
  options.modules.services.ai.open-webui = {
    enable = mkEnableOption "Open WebUI for Ollama";

    serviceName = mkOption {
      type = types.str;
      default = "Open WebUI";
      description = "Service name used for appData registration";
    };

    domain = mkOption {
      type = types.str;
      default = "chat.${config.networking.domain}";
      description = "Domain for Open WebUI";
    };

    port = mkOption {
      type = types.port;
      default = 3095;
      description = "Port for Open WebUI";
    };

    ollamaHost = mkOption {
      type = types.str;
      default = "http://tristons-workstation:11434";
      description = "Ollama API endpoint URL";
    };
  };

  config = mkIf cfg.enable {
    modules.services.appData.services.${cfg.serviceName} = {
      owner = "root";
      group = "root";
    };

    services.open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = cfg.port;
      environment = {
        TZ = config.time.timeZone;
        OLLAMA_BASE_URL = cfg.ollamaHost;
        WEBUI_AUTH = "True";
        ENABLE_SIGNUP = "True";
      };
    };

    # Ensure Tailscale is running before starting open-webui
    # Required for resolving remote Ollama backend via Tailscale DNS
    systemd.services.open-webui = {
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
    };

    # Caddy reverse proxy
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
