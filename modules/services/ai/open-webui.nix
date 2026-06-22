{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.open-webui;
in
{
  options.modules.services.ai.open-webui = {
    enable = mkEnableOption "Open WebUI for local and API LLMs";

    domain = mkOption {
      type = types.str;
      default = "chat.${config.networking.domain}";
    };

    port = mkOption {
      type = types.port;
      default = 3095;
    };

    ollamaHost = mkOption {
      type = types.str;
      default = "http://localhost:${toString config.modules.services.ai.ollama.port}";
      description = "Ollama API endpoint for local models. Override when Ollama runs on a remote host.";
    };

    # Path to an EnvironmentFile with secrets. Loaded by the systemd unit so
    # the values are never written to the Nix store. Suggested contents:
    #
    #   WEBUI_SECRET_KEY=<random 32+ char string>
    #   OPENAI_API_KEYS=<key1>;<key2>   # semicolon-separated for multiple providers
    #
    # Encrypt with agenix: ./encrypt-secret.sh -n open-webui-env.age -e
    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to an agenix-decrypted EnvironmentFile with secrets.";
    };

    # Extra OpenAI-compatible API base URLs beyond Ollama (semicolon-separated).
    # Open WebUI pairs each URL with the corresponding entry in OPENAI_API_KEYS
    # (from environmentFile) by position.
    #
    # Example: add Anthropic claude-compatible proxy or OpenAI directly.
    #   "https://api.openai.com/v1"
    #   "https://api.anthropic.com/v1"  (requires openai-compatible wrapper)
    apiBaseUrls = mkOption {
      type = types.listOf types.str;
      default = [ "http://127.0.0.1:${toString config.modules.services.ai.litellm.port}" ];
      description = "Additional OpenAI-compatible API base URLs (positionally matched with OPENAI_API_KEYS).";
    };

    # --- Memory / RAG options ---

    enableQdrant = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Connect Open WebUI to a local Qdrant instance for vector-backed RAG.
        Requires modules.services.ai.qdrant.enable = true on the same host.
        Open WebUI will use Qdrant as its vector store for document embeddings
        instead of the default Chroma.
      '';
    };

    embeddingModel = mkOption {
      type = types.str;
      default = "nomic-embed-text:latest";
      description = ''
        Ollama model used to generate embeddings for RAG.
        nomic-embed-text is fast and small (274MB). Pull it alongside your
        main model: add it to modules.services.ai.ollama.loadModels.
      '';
    };

    enableWebSearch = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable web search tool for agents. Uses SearXNG by default.
        Set SEARXNG_QUERY_URL in environmentFile to point at your instance,
        or configure a different provider via RAG_WEB_SEARCH_ENGINE.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = cfg.port;
      environment = {
        TZ = config.time.timeZone;

        # --- Local Ollama backend ---
        OLLAMA_BASE_URL = cfg.ollamaHost;
        ENABLE_OLLAMA_API = "true";

        # --- Additional API providers ---
        # Populated when apiBaseUrls is non-empty; positionally matched with
        # OPENAI_API_KEYS (semicolon-separated) from environmentFile.
        OPENAI_API_BASE_URLS = mkIf (cfg.apiBaseUrls != [])
          (concatStringsSep ";" cfg.apiBaseUrls);

        # --- RAG / Vector memory ---
        VECTOR_DB = mkIf cfg.enableQdrant "qdrant";
        QDRANT_URI = mkIf cfg.enableQdrant
          "http://127.0.0.1:${toString config.modules.services.ai.qdrant.port}";

        # Use Ollama for local embeddings (avoids OpenAI embedding API costs).
        RAG_EMBEDDING_ENGINE = "ollama";
        RAG_OLLAMA_BASE_URL = cfg.ollamaHost;
        RAG_EMBEDDING_MODEL = cfg.embeddingModel;

        # Enable per-user "Memories" feature (stores extracted facts about you
        # across conversations — separate from the vector/document RAG above).
        ENABLE_MEMORY_TOOL = "true";

        # --- Web search ---
        ENABLE_RAG_WEB_SEARCH = if cfg.enableWebSearch then "true" else "false";

        WEBUI_AUTH = "true";
        ENABLE_SIGNUP = "true";
      };
      environmentFile = cfg.environmentFile;
    };

    # Tailscale and Qdrant must be up before Open WebUI starts.
    systemd.services.open-webui = {
      after = [ "tailscaled.service" ]
        ++ optionals cfg.enableQdrant [ "qdrant.service" ];
      wants = [ "tailscaled.service" ]
        ++ optionals cfg.enableQdrant [ "qdrant.service" ];
    };

    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
