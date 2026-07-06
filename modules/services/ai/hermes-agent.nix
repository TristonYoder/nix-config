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

    stateDir = mkOption {
      type = types.str;
      default = "/data/hermes";
      description = ''
        Base directory for all Hermes state — config.yaml, memories, skills,
        sessions, cron, and the workspace. Passed straight through to
        services.hermes-agent.stateDir. Defaults onto /data (david's bulk
        storage) rather than upstream's /var/lib/hermes so state survives
        independently of the root disk and sits next to other appdata.
      '';
    };

    obsidianVault = mkOption {
      type = types.str;
      default = "${cfg.stateDir}/obsidian";
      description = ''
        Path to an Obsidian-compatible vault where Hermes charts its memory
        (MEMORY.md, USER.md) and knowledge (skills/) as plain markdown notes,
        instead of leaving them buried inside HERMES_HOME. At activation, the
        memory files and skills directory are symlinked into
        "''${obsidianVault}/Hermes/" — existing content is moved in once,
        never overwritten, so the agent keeps reading/writing the same files
        while they're also a browsable, syncable Obsidian vault (pair with
        modules.services.storage.syncthing to reach it from other devices).
      '';
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
      stateDir = cfg.stateDir;

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

      environment = optionalAttrs (cfg.homeRoom != null) {
        MATRIX_HOME_ROOM = cfg.homeRoom;
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
    #
    # user/group/stateDir come from services.hermes-agent (not hardcoded) so this
    # never drifts from the actual service identity again — it previously pointed
    # at a "hermes-agent" user/path that nothing in this repo ever creates.
    system.activationScripts.hermesAgentSoul = mkIf (cfg.soul != null) {
      text = ''
        install -o ${config.services.hermes-agent.user} -g ${config.services.hermes-agent.group} -m 0660 \
          ${pkgs.writeText "hermes-SOUL.md" cfg.soul} \
          ${config.services.hermes-agent.stateDir}/.hermes/SOUL.md
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };

    # Chart memory (MEMORY.md, USER.md) and knowledge (skills/) into an Obsidian
    # vault. Only the two memory *files* are symlinked (not their parent dir —
    # that dir is systemd-tmpfiles managed by the upstream module, and replacing
    # a tmpfiles-owned directory with a symlink causes it to fight every switch).
    # skills/ isn't tmpfiles-managed at all, so the whole directory is safe to
    # symlink. Idempotent: existing on-disk content is moved into the vault
    # exactly once (first switch after enabling), never overwritten afterward.
    system.activationScripts.hermesAgentVault = {
      text = let
        user = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        stateDir = config.services.hermes-agent.stateDir;
        vaultDir = "${cfg.obsidianVault}/Hermes";
        # Container mode only bind-mounts stateDir (at a different internal
        # path, /data). An absolute host symlink target like
        # /data/hermes/obsidian/... doesn't exist inside that namespace, so
        # the container's entrypoint fails to dereference it on chown. Vault
        # links must be relative to resolve under both the host path and the
        # container's remapped one — which requires obsidianVault to live
        # under stateDir.
        vaultRelToState =
          if lib.hasPrefix "${stateDir}/" cfg.obsidianVault
          then lib.removePrefix "${stateDir}/" cfg.obsidianVault
          else throw "modules.services.ai.hermes-agent.obsidianVault must be nested under stateDir (${stateDir}) so the container can see it";
      in ''
        mkdir -p ${vaultDir}
        chown ${user}:${group} ${cfg.obsidianVault} ${vaultDir}

        migrate_file() {
          local name="$1"
          local src="${stateDir}/.hermes/memories/$name"
          local dst="${vaultDir}/$name"
          if [ ! -e "$dst" ]; then
            if [ -f "$src" ] && [ ! -L "$src" ]; then
              mv "$src" "$dst"
            else
              touch "$dst"
            fi
            chown ${user}:${group} "$dst"
          fi
          # Relative: from .hermes/memories/ up to stateDir root, into the vault.
          ln -sfn "../../${vaultRelToState}/Hermes/$name" "$src"
        }
        migrate_file "MEMORY.md"
        migrate_file "USER.md"

        skills_src="${stateDir}/.hermes/skills"
        skills_dst="${vaultDir}/Skills"
        if [ ! -e "$skills_dst" ]; then
          if [ -d "$skills_src" ] && [ ! -L "$skills_src" ]; then
            mv "$skills_src" "$skills_dst"
          else
            mkdir -p "$skills_dst"
          fi
          chown -R ${user}:${group} "$skills_dst"
        fi
        # Relative: from .hermes/ up to stateDir root, into the vault.
        ln -sfn "../${vaultRelToState}/Hermes/Skills" "$skills_src"
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };
  };
}
