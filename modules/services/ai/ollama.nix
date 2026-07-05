{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.ollama;
in
{
  options.modules.services.ai.ollama = {
    enable = mkEnableOption "Ollama local LLM server";

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address Ollama listens on. Default exposes on all interfaces for LAN access.";
    };

    port = mkOption {
      type = types.port;
      default = 11434;
    };

    models = mkOption {
      type = types.str;
      default = "/var/lib/ollama/models";
      description = "Directory to store downloaded models.";
    };

    loadModels = mkOption {
      type = types.listOf types.str;
      default = [ "hermes3:latest" ];
      description = ''
        Models to pull on startup. Hermes 3 (NousResearch) is the default:
        strong tool-calling, function-calling, and agentic reasoning.
        Search https://ollama.com/library for alternatives.
      '';
    };

    # RTX 4080 uses CUDA; workstation default
    useCuda = mkOption {
      type = types.bool;
      default = false;
      description = "Use CUDA-accelerated Ollama build (for NVIDIA GPUs).";
    };

    # Open Ollama port only on specific network interfaces.
    # Leave empty to keep the port firewalled on all interfaces.
    # Example: set to ["enp7s0"] to expose only on the Core Services VLAN NIC.
    allowedInterfaces = mkOption {
      type = types.listOf types.str;
      default = [];
    };
  };

  config = mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = if cfg.useCuda then pkgs.ollama-cuda else pkgs.ollama;
      host = cfg.host;
      port = cfg.port;
      models = cfg.models;
      loadModels = cfg.loadModels;
    };

    # Open Ollama only on the declared interfaces (not globally).
    networking.firewall.interfaces = mkIf (cfg.allowedInterfaces != [])
      (listToAttrs (map (iface: {
        name = iface;
        value.allowedTCPPorts = [ cfg.port ];
      }) cfg.allowedInterfaces));
  };
}
