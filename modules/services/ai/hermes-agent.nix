{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.hermes-agent;
in
{
  options.modules.services.ai.hermes-agent = {
    enable = mkEnableOption "Hermes Agent (NousResearch)";

    model = mkOption {
      type = types.str;
      default = "anthropic/claude-opus-4-8";
      description = "Default LLM model for Hermes. Should be a LiteLLM-routed name or direct provider string.";
    };

    inferenceUrl = mkOption {
      type = types.nullOr types.str;
      default = "http://127.0.0.1:4000";
      description = "Base URL for the LiteLLM proxy. Set null to use provider URLs directly.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Agenix-decrypted environment file. Must contain ANTHROPIC_API_KEY (or provider key) and LITELLM_MASTER_KEY.";
    };

    containerMode = mkOption {
      type = types.bool;
      default = true;
      description = "Run Hermes in a Docker container (supports apt/pip/npm for agent-installed tools).";
    };

    extraVolumes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional volume mounts for the container.";
    };
  };

  config = mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;

      settings.model.default = cfg.model;

      # Point at LiteLLM proxy if set
      settings.model.base_url = mkIf (cfg.inferenceUrl != null) cfg.inferenceUrl;

      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;

      container = mkIf cfg.containerMode {
        enable = true;
        backend = "docker";
        extraVolumes = cfg.extraVolumes;
        # RTX 4080 available if needed for local inference inside the container
        extraOptions = [ "--gpus" "all" ];
      };
    };
  };
}
