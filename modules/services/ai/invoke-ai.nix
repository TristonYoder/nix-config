{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.invokeAi;
in
{
  options.modules.services.ai.invokeAi = {
    enable = mkEnableOption "InvokeAI Stable Diffusion image generation";

    domain = mkOption {
      type = types.str;
      default = "invoke.${config.networking.domain}";
    };

    port = mkOption {
      type = types.int;
      default = 9090;
    };

    proxyHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "If set, proxy to this host instead of running InvokeAI locally. Use for david proxying to tristons-workstation.";
    };
  };

  config = mkIf cfg.enable {
    # Local service — only when not in proxy mode
    virtualisation.oci-containers.containers = mkIf (cfg.proxyHost == null) {
      "invoke-ai" = {
        image = "ghcr.io/invoke-ai/invokeai:latest";
        ports = [ "127.0.0.1:${toString cfg.port}:9090" ];
        volumes = [ "/var/lib/invoke-ai:/invokeai" ];
        extraOptions = [ "--gpus=all" "--runtime=nvidia" ];
      };
    };

    # NVIDIA container toolkit — required for GPU passthrough in OCI containers
    hardware.nvidia-container-toolkit.enable = mkIf (cfg.proxyHost == null) true;

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      reverseProxyHost = mkIf (cfg.proxyHost != null) cfg.proxyHost;
      displayName = "InvokeAI";
      category = "ai";
      icon = "invoke-ai";
      monitor = false; # GPU workstation service, not always reachable
    };
  };
}
