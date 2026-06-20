{ config, lib, ... }:

# Hermes stack bundle — one enable wires the full AI infrastructure:
#
#   hermes-agent  — NousResearch Hermes Agent (orchestration, memory, gateway)
#   litellm       — model routing proxy (local Ollama ↔ Claude API)
#   open-webui    — human-facing chat UI (connects via LiteLLM)
#   qdrant        — vector store for RAG and semantic memory
#
# Typical host config (environmentFile is the only required override):
#
#   modules.services.ai.hermes = {
#     enable = true;
#     environmentFile = config.age.secrets.hermes-env.path;
#   };
#
# For Ollama on tristons-workstation set modules.services.ai.ollama there.

with lib;
let
  cfg = config.modules.services.ai.hermes;
  litellmUrl = "http://127.0.0.1:${toString config.modules.services.ai.litellm.port}";
in
{
  options.modules.services.ai.hermes = {
    enable = mkEnableOption "Hermes AI stack (agent + LiteLLM + Open WebUI + Qdrant)";

    domain = mkOption {
      type = types.str;
      default = "chat.${config.networking.domain}";
      description = "Domain for the Open WebUI interface.";
    };

    ollamaHost = mkOption {
      type = types.str;
      default = "http://tristons-workstation.${config.networking.domain}:11434";
      description = "Ollama endpoint on tristons-workstation for local model inference.";
    };

    vaultPath = mkOption {
      type = types.str;
      default = "/data/tristonyoder/home/vaults/hermes-brain";
      description = "HERMES_HOME: git-backed Obsidian vault.";
    };

    nixConfigPath = mkOption {
      type = types.str;
      default = "/data/tristonyoder/home/Projects/nix-config";
      description = "nix-config repo path, mounted read-only into Hermes for PR operations.";
    };

    # A single EnvironmentFile shared across hermes-agent and litellm.
    # Minimum contents:
    #   LITELLM_MASTER_KEY=<random>        # key Hermes + Open WebUI use to auth
    #   OPENAI_API_KEY=<same-as-above>     # Open WebUI sends this header
    #   ANTHROPIC_API_KEY=<key>            # for Claude via LiteLLM
    #   GITHUB_TOKEN=<token>               # repo + pull_request scopes
    #   WEBUI_SECRET_KEY=<random>          # Open WebUI session secret
    # Optional gateway tokens:
    #   TELEGRAM_BOT_TOKEN=<token>
    #   MATRIX_ACCESS_TOKEN=<token>
    #   MATRIX_HOMESERVER_URL=<url>
    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    enableWebSearch = mkOption {
      type = types.bool;
      default = false;
      description = "Enable web search in Open WebUI. Requires SEARXNG_QUERY_URL in environmentFile.";
    };
  };

  config = mkIf cfg.enable {

    # --- LiteLLM: model routing -------------------------------------------------
    modules.services.ai.litellm = {
      enable = true;
      environmentFile = cfg.environmentFile;
      models = [
        {
          # Fast, private, local — default for most tasks
          name     = "fast";
          model    = "ollama/hermes3";
          apiBase  = cfg.ollamaHost;
        }
        {
          # Embeddings for RAG (nomic-embed-text via Ollama)
          name     = "embed";
          model    = "ollama/nomic-embed-text";
          apiBase  = cfg.ollamaHost;
        }
        {
          # Complex reasoning — routed to Claude
          name      = "smart";
          model     = "anthropic/claude-sonnet-4-6";
          apiKeyEnv = "ANTHROPIC_API_KEY";
        }
      ];
    };

    # --- Hermes Agent -----------------------------------------------------------
    modules.services.ai.hermes-agent = {
      enable = true;
      vaultPath     = cfg.vaultPath;
      nixConfigPath = cfg.nixConfigPath;
      inferenceUrl  = litellmUrl;
      environmentFile = cfg.environmentFile;
    };

    # --- Qdrant: vector store ---------------------------------------------------
    modules.services.ai.qdrant.enable = true;

    # --- Open WebUI: human-facing chat UI --------------------------------------
    # Routes all model calls through LiteLLM so humans get the same model roster
    # as the agent. Also keeps direct Ollama connection for the model browser UI.
    modules.services.ai.open-webui = {
      enable          = true;
      domain          = cfg.domain;
      ollamaHost      = cfg.ollamaHost;
      enableQdrant    = true;
      enableWebSearch = cfg.enableWebSearch;
      environmentFile = cfg.environmentFile;
      # LiteLLM appears as an additional OpenAI-compatible provider.
      # OPENAI_API_KEY (from environmentFile) is used for auth.
      apiBaseUrls     = [ litellmUrl ];
    };
  };
}
