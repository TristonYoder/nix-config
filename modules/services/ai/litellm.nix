{ config, lib, pkgs, ... }:

# LiteLLM proxy — unified model routing layer.
#
# Sits between Hermes Agent (and Open WebUI) and the actual model providers.
# All AI calls go through one OpenAI-compatible endpoint; routing rules decide
# whether a given request goes to local Ollama (fast/private) or the Claude API
# (complex reasoning).
#
# Hermes connects via HERMES_MODEL_BASE = http://127.0.0.1:<port>.
# Open WebUI connects via OPENAI_API_BASE_URLS = http://127.0.0.1:<port>.

with lib;
let
  cfg = config.modules.services.ai.litellm;

  # Generate config.yaml from the declared model list.
  # LiteLLM reads api_key as os.environ/VAR_NAME to avoid storing keys in the
  # config file (which ends up in the Nix store).
  litellmConfig = pkgs.writeText "litellm-config.yaml" (
    "model_list:\n"
    + concatMapStrings (m:
        "  - model_name: ${m.name}\n"
        + "    litellm_params:\n"
        + "      model: ${m.model}\n"
        + optionalString (m.apiBase != null)
            "      api_base: ${m.apiBase}\n"
        + optionalString (m.apiKeyEnv != null)
            "      api_key: os.environ/${m.apiKeyEnv}\n"
      ) cfg.models
    + "\nlitellm_settings:\n"
    + "  telemetry: false\n"
    + "  drop_params: true\n"
    + "\ngeneral_settings:\n"
    + "  master_key: os.environ/LITELLM_MASTER_KEY\n"
  );

in
{
  options.modules.services.ai.litellm = {
    enable = mkEnableOption "LiteLLM model routing proxy";

    port = mkOption {
      type = types.port;
      default = 4000;
    };

    models = mkOption {
      description = "Model list exposed by the proxy. Each entry becomes a named model in the OpenAI-compatible API.";
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Name clients use when calling this model (e.g. 'fast', 'smart').";
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
            description = "Environment variable name holding the API key (e.g. 'ANTHROPIC_API_KEY').";
          };
        };
      });
      default = [];
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Agenix-decrypted EnvironmentFile with secrets. Must include:
          LITELLM_MASTER_KEY=<random string>   # key clients use to authenticate
        And any API keys referenced in models[*].apiKeyEnv:
          ANTHROPIC_API_KEY=<key>
          OPENAI_API_KEY=<key>                 # if using OpenAI models
      '';
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/berriai/litellm:main-latest";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.litellm = {
      image = cfg.image;
      volumes = [ "${litellmConfig}:/app/config.yaml:ro" ];
      cmd = [
        "--config" "/app/config.yaml"
        "--port" (toString cfg.port)
        "--num_workers" "4"
      ];
      environment.LITELLM_TELEMETRY = "false";
      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;
      # Bind only to localhost — Hermes and Open WebUI reach it via 127.0.0.1.
      ports = [ "127.0.0.1:${toString cfg.port}:${toString cfg.port}" ];
    };
  };
}
