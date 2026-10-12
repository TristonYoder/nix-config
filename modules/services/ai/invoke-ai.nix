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

    # Open the container port only on specific network interfaces, mirroring
    # modules/services/ai/ollama.nix. Needed because the proxying host (david)
    # reaches this one over the LAN, not localhost — leave empty to keep the
    # port firewalled on all interfaces.
    allowedInterfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Interfaces to open cfg.port on (e.g. [\"enp7s0\"] for the Core Services VLAN). Only relevant when proxyHost is null.";
    };
  };

  config = mkIf cfg.enable {
    # Local service — only when not in proxy mode
    virtualisation.oci-containers.containers = mkIf (cfg.proxyHost == null) {
      "invoke-ai" = {
        image = "ghcr.io/invoke-ai/invokeai:latest";
        # No host IP prefix — binds 0.0.0.0 so david's reverse proxy can
        # reach it over the LAN. Reachability is restricted via the firewall
        # rule below instead of via loopback-only binding.
        ports = [ "${toString cfg.port}:9090" ];
        volumes = [ "/var/lib/invoke-ai:/invokeai" ];
        extraOptions = [ "--gpus=all" "--runtime=nvidia" ];
      };
    };

    # This host's oci-containers.backend default may not be "docker" (e.g.
    # desktop/workstation hosts default to podman) — the --gpus/--runtime
    # flags above are docker-specific, so pin both explicitly, as every other
    # oci-container service module in this repo does.
    virtualisation.docker.enable = mkIf (cfg.proxyHost == null) true;
    virtualisation.oci-containers.backend = mkIf (cfg.proxyHost == null) "docker";

    # NVIDIA container toolkit — required for GPU passthrough in OCI containers
    hardware.nvidia-container-toolkit.enable = mkIf (cfg.proxyHost == null) true;

    networking.firewall.interfaces = mkIf (cfg.proxyHost == null && cfg.allowedInterfaces != [])
      (listToAttrs (map (iface: {
        name = iface;
        value.allowedTCPPorts = [ cfg.port ];
      }) cfg.allowedInterfaces));

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
