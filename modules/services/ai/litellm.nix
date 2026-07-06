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
          exposeModelName = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Also register this route under its raw model name (everything
              in `model` after the first '/', e.g. "anthropic/claude-sonnet-4.6"
              or "hermes3") in addition to `name`. Lets clients pick either the
              tier alias (fast/smart/local/...) — which can be repointed at a
              different underlying model later without callers noticing — or
              the specific model directly, e.g. from Open WebUI's dropdown.
            '';
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

    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Arbitrary LiteLLM settings merged (via //) into services.litellm.settings.
        Top-level keys override the generated ones wholesale — e.g. passing
        extraSettings.litellm_settings = {...} replaces the generated
        litellm_settings (including telemetry=false) entirely.
        Use for router_settings, callbacks, or other config not exposed as typed options.
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
        model_list =
          let
            # Everything after the first '/' in the litellm model string, e.g.
            # "openrouter/anthropic/claude-sonnet-4.6" -> "anthropic/claude-sonnet-4.6",
            # "ollama/hermes3" -> "hermes3".
            rawNameOf = m: removePrefix ("${head (splitString "/" m.model)}/") m.model;
            mkEntry = modelName: m: {
              model_name = modelName;
              litellm_params = {
                model = m.model;
              } // optionalAttrs (m.apiBase != null) {
                api_base = m.apiBase;
              } // optionalAttrs (m.apiKeyEnv != null) {
                api_key = "os.environ/${m.apiKeyEnv}";
              };
            };
          in
          concatMap (m:
            [ (mkEntry m.name m) ]
            ++ optional (m.exposeModelName && rawNameOf m != m.name) (mkEntry (rawNameOf m) m)
          ) cfg.models;

        litellm_settings = {
          telemetry = false;
          drop_params = true;
        };

        general_settings = optionalAttrs cfg.requireAuth {
          master_key = "os.environ/LITELLM_MASTER_KEY";
        };
      } // cfg.extraSettings;
    };
  };
}
