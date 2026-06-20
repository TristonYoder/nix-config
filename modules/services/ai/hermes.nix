{ config, lib, ... }:

# Hermes: server-side AI agent stack for david.
#
# Enables and wires together the three server-side components:
#   - Open WebUI  — chat/agent UI, accessible via Caddy reverse proxy
#   - Qdrant       — local vector store for RAG and semantic memory
#   - Inference    — points at Ollama on tristons-workstation (remote CUDA)
#
# Typical host config:
#
#   modules.services.ai.hermes = {
#     enable = true;
#     environmentFile = config.age.secrets.open-webui-env.path;
#   };
#
# For Ollama on tristons-workstation, set modules.services.ai.ollama there.

with lib;
let
  cfg = config.modules.services.ai.hermes;
in
{
  options.modules.services.ai.hermes = {
    enable = mkEnableOption "Hermes AI agent stack (Open WebUI + Qdrant + remote Ollama)";

    domain = mkOption {
      type = types.str;
      default = "chat.${config.networking.domain}";
    };

    inferenceHost = mkOption {
      type = types.str;
      default = "http://tristons-workstation.${config.networking.domain}:11434";
      description = "Ollama API endpoint for local model inference.";
    };

    # Path to an agenix-decrypted EnvironmentFile. Required for production.
    # Minimum contents:
    #   WEBUI_SECRET_KEY=<openssl rand -base64 32>
    # Optional (add API providers beyond Ollama):
    #   OPENAI_API_KEYS=<key1>;<key2>
    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    # Additional OpenAI-compatible base URLs (positionally matched with
    # OPENAI_API_KEYS in environmentFile).
    apiBaseUrls = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "https://api.openai.com/v1" ];
    };

    enableWebSearch = mkOption {
      type = types.bool;
      default = false;
      description = "Enable web search tool (requires SEARXNG_QUERY_URL in environmentFile).";
    };
  };

  config = mkIf cfg.enable {
    modules.services.ai.qdrant.enable = true;

    modules.services.ai.open-webui = {
      enable = true;
      domain = cfg.domain;
      ollamaHost = cfg.inferenceHost;
      enableQdrant = true;
      environmentFile = cfg.environmentFile;
      apiBaseUrls = cfg.apiBaseUrls;
      enableWebSearch = cfg.enableWebSearch;
    };
  };
}
