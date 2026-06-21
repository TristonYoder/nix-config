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
      default = "http://127.0.0.1:${toString config.modules.services.ai.litellm.port}";
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
    # olm is required by mautrix[encryption] for Matrix E2E. nixpkgs marks it
    # insecure due to the upstream project being archived, but it's functional
    # and there's no replacement for python-olm in the mautrix ecosystem yet.
    nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;

      # Use optionalAttrs so base_url is set as a plain YAML string, not a
      # mkIf conditional. The upstream hermes module serializes Nix mkIf into
      # a {_type: if, ...} YAML dict, and runtime_provider.py calls .strip()
      # on that dict → AttributeError: 'dict' object has no attribute 'strip'.
      #
      # provider=custom:litellm-proxy: hermes resolves this against the
      # providers.litellm-proxy entry below, which supplies base_url + key_env
      # so hermes sends LITELLM_MASTER_KEY as the API key.
      settings.model = { default = cfg.model; provider = "custom:litellm-proxy"; }
        // optionalAttrs (cfg.inferenceUrl != null) { base_url = cfg.inferenceUrl; };

      # Named custom provider so hermes knows the base URL and which env var
      # holds the API key for the LiteLLM proxy. Omitted when inferenceUrl is null.
      settings = mkIf (cfg.inferenceUrl != null) {
        providers.litellm-proxy = {
          api = cfg.inferenceUrl;
          key_env = "LITELLM_MASTER_KEY";
        };
      };

      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;

      # Matrix platform dependencies — uses the upstream 'matrix' pyproject.toml
      # optional-dependency group, which includes mautrix[encryption]==0.21.0,
      # aiosqlite, asyncpg, and aiohttp-socks into the sealed uv venv.
      extraDependencyGroups = [ "matrix" ];

      container = mkIf cfg.containerMode {
        enable = true;
        backend = "docker";
        extraVolumes = cfg.extraVolumes;
      };
    };
  };
}
