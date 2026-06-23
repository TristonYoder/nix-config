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

    homeRoom = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Matrix room ID to use as Hermes's persistent home room (sets MATRIX_HOME_ROOM).
        When set, Hermes re-joins this room on startup without requiring /sethome.
        Must be set alongside HERMES_MANAGED=true in the environment file to block
        the /sethome command (prevents accidental home-room override).
      '';
    };

    extraVolumes = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional volume mounts for the container.";
    };

    soul = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SOUL.md content (hermes system prompt / persona). Written to the working directory at activation via services.hermes-agent.documents. Null uses hermes's built-in default.";
    };

    matrixHomeRoom = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Matrix room ID to use as the hermes home room (MATRIX_HOME_ROOM env var). Set so /sethome is not required after each restart.";
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

      # Use optionalAttrs (not mkIf) so all values are plain YAML strings.
      # The upstream hermes module serializes mkIf into {_type: if, ...} dicts,
      # and runtime_provider.py calls .strip() on those → AttributeError.
      #
      # provider=custom:litellm-proxy: hermes resolves this against the
      # providers.litellm-proxy entry, reads LITELLM_MASTER_KEY from env,
      # and sends it as the API key so LiteLLM auth succeeds.
      settings = {
        model = { default = cfg.model; provider = "custom:litellm-proxy"; }
          // optionalAttrs (cfg.inferenceUrl != null) { base_url = cfg.inferenceUrl; };
      } // optionalAttrs (cfg.inferenceUrl != null) {
        providers.litellm-proxy = {
          api = cfg.inferenceUrl;
          key_env = "LITELLM_MASTER_KEY";
        };
      };

      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;

      environment = optionalAttrs (cfg.matrixHomeRoom != null) {
        MATRIX_HOME_ROOM = cfg.matrixHomeRoom;
      };

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

    # Write SOUL.md to HERMES_HOME (.hermes/), where load_soul_md() reads it.
    # Cannot use services.hermes-agent.documents — that installs to workingDirectory
    # (workspace), which hermes never checks for the persona slot.
    system.activationScripts.hermesAgentSoul = mkIf (cfg.soul != null) {
      text = ''
        install -o hermes-agent -g hermes-agent -m 0660 \
          ${pkgs.writeText "hermes-SOUL.md" cfg.soul} \
          /var/lib/hermes-agent/.hermes/SOUL.md
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };
  };
}
