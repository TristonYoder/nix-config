{ config, lib, pkgs, ... }:

# Wraps services.litellm (nixpkgs native module).
# Adds project-specific defaults: localhost binding, telemetry off,
# and a typed model-list option that maps to services.litellm.settings.

with lib;
let
  cfg = config.modules.services.ai.litellm;
in
{
  options.modules.services.ai.litellm = {
    enable = mkEnableOption "LiteLLM model routing proxy";

    port = mkOption {
      type = types.port;
      default = 4000;
    };

    models = mkOption {
      description = "Models exposed by the proxy. Each entry becomes a named model in the OpenAI-compatible API.";
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Name clients use (e.g. 'fast', 'smart').";
          };
          model = mkOption {
            type = types.str;
            description = "LiteLLM model string, e.g. 'ollama/hermes3' or 'anthropic/claude-sonnet-4-6'.";
          };
          apiBase = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Override API base URL (required for Ollama and other local endpoints).";
          };
          apiKeyEnv = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Environment variable name holding the API key, e.g. 'ANTHROPIC_API_KEY'. LiteLLM reads it as os.environ/<name>.";
          };
        };
      });
      default = [];
    };

    requireAuth = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Require clients to authenticate with LITELLM_MASTER_KEY.
        Safe to disable when LiteLLM is localhost-only and all callers
        are trusted local services (hermes, open-webui, etc.).
      '';
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Agenix-decrypted EnvironmentFile. Must include:
          LITELLM_MASTER_KEY=<random>    # key clients use to authenticate (if requireAuth = true)
        And any API keys referenced in models[*].apiKeyEnv:
          ANTHROPIC_API_KEY=<key>
      '';
    };
  };

  config = mkIf cfg.enable {
    services.litellm = {
      enable = true;
      host = "127.0.0.1";
      port = cfg.port;
      environmentFile = cfg.environmentFile;

      settings = {
        model_list = map (m: {
          model_name = m.name;
          litellm_params = {
            model = m.model;
          } // optionalAttrs (m.apiBase != null) {
            api_base = m.apiBase;
          } // optionalAttrs (m.apiKeyEnv != null) {
            api_key = "os.environ/${m.apiKeyEnv}";
          };
        }) cfg.models;

        litellm_settings = {
          telemetry = false;
          drop_params = true;
        };

        general_settings = optionalAttrs cfg.requireAuth {
          master_key = "os.environ/LITELLM_MASTER_KEY";
        };
      };
    };
  };
}
