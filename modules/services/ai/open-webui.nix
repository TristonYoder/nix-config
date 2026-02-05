{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.open-webui;
in
{
  options.modules.services.ai.open-webui = {
    enable = mkEnableOption "Open WebUI for Ollama";

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
    services.open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = cfg.port;
      environment = {
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
    modules.services.vHosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
