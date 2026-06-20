{ config, lib, pkgs, ... }:

# Hermes Agent service module.
#
# Runs the NousResearch Hermes Agent as a Docker container with:
#   - HERMES_HOME pointed at a git-backed Obsidian vault on /data
#   - A sandboxed `hermes-executor` user on the host for shell execution
#   - SSH keypair auto-generated on first deploy
#   - Core skills seeded into the vault on first deploy
#
# The agent submits PRs to the nix-config repo for any infrastructure
# requests (persistent containers, VMs) rather than acting on the host
# directly. See skills/core/nix-config-pr/SKILL.md.

with lib;
let
  cfg = config.modules.services.ai.hermes-agent;

  # ---------------------------------------------------------------------------
  # Core skills seeded into the vault on first deploy.
  # Written only if the destination file doesn't already exist — never
  # overwritten, so the agent's own improvements to these files are preserved.
  # ---------------------------------------------------------------------------

  skillVaultGit = pkgs.writeText "vault-git-SKILL.md" ''
    ---
    name: vault-git
    description: Commit memory and skill changes to the vault git repo after every write
    version: 1.0.0
    category: core
    tags: [memory, git, vault]
    always_active: true
    ---

    ## Purpose

    This vault is a git repository. After every operation that modifies memory or
    skills, commit so the vault maintains a meaningful, human-readable history.

    ## When to commit

    After any of these — and only after a write lands, not during reads:
    - `memory` tool call (add / replace / remove)
    - `skill_manage` tool call (create or update)
    - Manual edits to MEMORY.md, USER.md, or SOUL.md

    ## How to commit

    ```bash
    git -C "$HERMES_HOME" add -A
    git -C "$HERMES_HOME" commit -m "<message>"
    ```

    ## Message format

    | Change             | Prefix    | Example                                           |
    |--------------------|-----------|---------------------------------------------------|
    | New memory entry   | remember  | remember: prefers btrfs for all new volumes       |
    | Updated entry      | update    | update: work hours changed to 7am–4pm             |
    | Removed entry      | forget    | forget: removed stale immich migration note       |
    | New skill          | skill     | skill: nixos-rebuild — github flake URL pattern   |
    | Skill improved     | improve   | improve: vault-git — push on remote available     |
    | SOUL.md change     | persona   | persona: adjusted tone to be more concise         |

    Keep messages under 72 characters. No "hermes:" prefix.

    ## Push after commit

    ```bash
    git -C "$HERMES_HOME" remote -v | grep -q origin && \
      git -C "$HERMES_HOME" push origin HEAD
    ```

    Safe to skip if offline — the commit still lands locally.
  '';

  skillNixEnvironments = pkgs.writeText "nix-environments-SKILL.md" ''
    ---
    name: nix-environments
    description: Escalation ladder for software environments — nix shell to persistent VMs
    version: 1.0.0
    category: core
    tags: [nix, environments, containers]
    always_active: true
    ---

    ## Escalation ladder

    Always choose the lowest level that meets the need.

    | Level | Mechanism                    | Approval | When to use                          |
    |-------|------------------------------|----------|--------------------------------------|
    | 0     | nix shell nixpkgs#pkg        | none     | One-off tool, no persistent state    |
    | 1     | shell.nix in vault/environments/ | none | Recurring env, want it reproducible  |
    | 2     | Docker container             | soft     | Full isolation or non-Nix deps       |
    | 3     | NixOS container (PR)         | required | Persistent across sessions, own net  |
    | 4     | MicroVM (PR)                 | required | Own kernel, maximum isolation        |

    Levels 3 and 4 require a PR to nix-config — see nix-config-pr skill.

    ## Level 0 — ad-hoc nix shell

    ```bash
    nix shell nixpkgs#ffmpeg -- ffmpeg -i input.mp4 output.webm
    nix shell nixpkgs#python3 nixpkgs#python3Packages.requests -- python3 script.py
    ```

    ## Level 1 — persistent shell.nix

    Write to $HERMES_HOME/environments/<name>/shell.nix:

    ```nix
    { pkgs ? import <nixpkgs> {} }:
    pkgs.mkShell {
      packages = with pkgs; [ python3 python3Packages.pandas ];
    }
    ```

    Create a matching SKILL.md, then commit both to the vault (vault-git skill).

    Activate:
    ```bash
    nix-shell $HERMES_HOME/environments/<name>/shell.nix --run "<cmd>"
    ```

    ## Safety boundary

    No approval needed:
    - nix shell, nix-shell, nix build
    - docker run with read-only mounts or writes under /data/hermes/workspaces/

    Requires PR (nix-config-pr skill):
    - nixos-rebuild, nix profile install
    - systemctl on system units
    - Anything modifying /etc or host system config
  '';

  skillNixConfigPr = pkgs.writeText "nix-config-pr-SKILL.md" ''
    ---
    name: nix-config-pr
    description: Submit a PR to nix-config to request persistent containers or VMs
    version: 1.0.0
    category: core
    tags: [nix, containers, github, approval]
    ---

    ## Purpose

    For Level 3 (NixOS container) and Level 4 (MicroVM) environment requests,
    write the NixOS config and open a PR against the nix-config repo. The human
    reviews in GitHub. Merging triggers CI which rebuilds david and provisions
    the environment automatically.

    ## Repo location

    /nix-config is a read-only mount of the nix-config repo.
    All git and gh commands must be run via the executor SSH session.

    ## Full workflow

    1. Write the container config (template below)
    2. Create branch:  agent/container-<name>  or  agent/vm-<name>
    3. Add config to:  hosts/david/containers/<name>.nix
    4. Add import to:  hosts/david/configuration.nix
    5. Commit and push the branch
    6. Open PR with gh pr create (template below)
    7. Tell the user a PR is open and needs their review
    8. Poll gh pr view --json state until state == "MERGED"
    9. Wait ~5 min for CI to rebuild david
    10. Add the new container's SSH endpoint to Hermes terminal backend config

    ## NixOS container config template

    File: hosts/david/containers/<name>.nix

    ```nix
    { pkgs, ... }: {
      containers.<name> = {
        autoStart = true;
        privateNetwork = true;
        hostAddress = "10.200.0.<host-n>";
        localAddress = "10.200.0.<container-n>";

        config = { pkgs, ... }: {
          environment.systemPackages = with pkgs; [ git ];
          services.openssh.enable = true;
          users.users.agent = {
            isNormalUser = true;
            # Embed the pubkey directly — keyFiles resolves at build time and
            # /var/lib/hermes-agent/ssh/ does not exist in the flake.
            # Read the key with: cat /var/lib/hermes-agent/ssh/id_ed25519.pub
            openssh.authorizedKeys.keys = [ "<paste-hermes-agent-pubkey-here>" ];
          };
          system.stateVersion = "25.05";
        };
      };
    }
    ```

    ## PR title and body template

    Title:   request: <name> container — <one-line purpose>

    Body:
    ```
    **Purpose**: <what this environment is for>
    **Level**: 3 (NixOS container) or 4 (MicroVM)
    **Resources**: ~<N>GB RAM, <N> cores
    **Network**: private (10.200.0.x), no external exposure
    **Justification**: <why nix shell or Docker isn't enough>

    Config: hosts/david/containers/<name>.nix
    ```

    ## Commands (run via executor SSH)

    The executor runs on the host. Use the host path to nix-config, not /nix-config
    (that mount only exists inside the Hermes container).

    ```bash
    NIXCFG="${cfg.nixConfigPath}"

    # Create branch and write files
    git -C "$NIXCFG" checkout main
    git -C "$NIXCFG" pull
    git -C "$NIXCFG" checkout -b agent/container-<name>
    # ... write files ...
    git -C "$NIXCFG" add -A
    git -C "$NIXCFG" commit -m "request: <name> container"
    git -C "$NIXCFG" push -u origin agent/container-<name>

    # Open PR
    gh --repo TristonYoder/nix-config pr create \
      --title "request: <name> container — <purpose>" \
      --body "<body>"

    # Poll for merge
    gh --repo TristonYoder/nix-config pr view <number> \
      --json state --jq .state
    # Returns MERGED when done
    ```
  '';

  initialSoul = pkgs.writeText "SOUL.md" ''
    You are Hermes, a personal AI agent running on Triston's homelab.

    You have persistent memory and grow with use. You operate across sessions,
    remembering projects, preferences, and workflows.

    Be direct and technical. Skip pleasantries. Get to the point.

    You have access to:
    - Local homelab infrastructure (david server, tristons-workstation with RTX 4080)
    - The nix-config repo — you can open PRs for infrastructure changes
    - A vault of skills and memories that persist across sessions
    - Local models via LiteLLM for fast/private tasks
    - Claude API for complex reasoning

    When you learn something worth keeping, write it to memory.
    When you solve something hard, write a skill.
    When you need persistent infrastructure, open a PR — don't act on the host directly.
    Always commit memory and skill changes to git after writing them.
  '';

in
{
  options.modules.services.ai.hermes-agent = {
    enable = mkEnableOption "Hermes Agent (NousResearch) AI agent service";

    vaultPath = mkOption {
      type = types.str;
      default = "/data/tristonyoder/home/vaults/hermes-brain";
      description = "HERMES_HOME: git-backed Obsidian vault for memories, skills, and sessions.";
    };

    nixConfigPath = mkOption {
      type = types.str;
      default = "/data/tristonyoder/home/Projects/nix-config";
      description = "Path to the nix-config repo. Mounted read-only; PR operations use the executor user.";
    };

    inferenceUrl = mkOption {
      type = types.str;
      default = "http://127.0.0.1:4000";
      description = "LiteLLM proxy base URL for all model calls.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Agenix-decrypted EnvironmentFile with secrets. Minimum:
          GITHUB_TOKEN=<token>          # repo + pull_request scopes
          OPENAI_API_KEY=<litellm-key>  # master key for the LiteLLM proxy

        Optional gateway tokens (one per enabled platform):
          TELEGRAM_BOT_TOKEN=<token>
          MATRIX_ACCESS_TOKEN=<token>
          MATRIX_HOMESERVER_URL=<url>
      '';
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/nousresearch/hermes-agent:latest";
    };

    gitEmail = mkOption {
      type = types.str;
      default = "hermes@${config.networking.hostName}";
    };

    vaultOwner = mkOption {
      type = types.str;
      default = "tristonyoder";
      description = "User that owns the vault directory on the host.";
    };
  };

  config = mkIf cfg.enable {

    # ---------------------------------------------------------------------------
    # hermes-executor: sandboxed host user the agent SSHs into for all shell
    # execution. Has git, gh, nix — but no sudo, cannot touch system config.
    # ---------------------------------------------------------------------------
    users.users.hermes-executor = {
      isSystemUser = true;
      group = "hermes-executor";
      home = "/var/lib/hermes-executor";
      createHome = true;
      shell = pkgs.bash;
      # authorized_keys is written at activation time by hermesAgentSshKey
      # (below) so the key path never needs to be known at eval/build time.
    };
    users.groups.hermes-executor = {};

    environment.systemPackages = [ pkgs.gh ];

    systemd.tmpfiles.rules = [
      "d /var/lib/hermes-agent     0750 root root -"
      "d /var/lib/hermes-agent/ssh 0700 root root -"
      "d /data/hermes/workspaces   0755 hermes-executor hermes-executor -"
    ];

    # ---------------------------------------------------------------------------
    # Generate the agent SSH keypair on first deploy.
    # Public key → hermes-executor authorized_keys.
    # Private key → mounted into the Hermes container at /root/.ssh.
    # Also writes an SSH client config so the container reaches the executor
    # with a plain `ssh localhost`.
    # ---------------------------------------------------------------------------
    system.activationScripts.hermesAgentSshKey = {
      text = ''
        KEY=/var/lib/hermes-agent/ssh/id_ed25519
        if [ ! -f "$KEY" ]; then
          ${pkgs.openssh}/bin/ssh-keygen \
            -t ed25519 \
            -f "$KEY" \
            -N "" \
            -C "hermes-agent@${config.networking.hostName}"
        fi

        # SSH client config used inside the container
        CONFIG=/var/lib/hermes-agent/ssh/config
        if [ ! -f "$CONFIG" ]; then
          cat > "$CONFIG" <<'EOF'
Host localhost
  User hermes-executor
  IdentityFile /root/.ssh/id_ed25519
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
          chmod 600 "$CONFIG"
        fi

        # Write pubkey into executor's authorized_keys at activation time.
        # authorizedKeys.keyFiles is eval-time (build-time) and can't reference
        # a path that doesn't exist in the Nix store, so we do it here instead.
        EXEC_SSH=/var/lib/hermes-executor/.ssh
        mkdir -p "$EXEC_SSH"
        chmod 700 "$EXEC_SSH"
        cp "$KEY.pub" "$EXEC_SSH/authorized_keys"
        chmod 600 "$EXEC_SSH/authorized_keys"
        chown -R hermes-executor:hermes-executor "$EXEC_SSH"
      '';
      deps = [ "users" "groups" ];
    };

    # ---------------------------------------------------------------------------
    # Initialise the vault on first deploy:
    #   - git init
    #   - create directory structure
    #   - seed core skills and initial memory files
    #   - .gitignore for binary / ephemeral files
    #   - initial commit
    # ---------------------------------------------------------------------------
    system.activationScripts.hermesVaultInit = {
      text = ''
        VAULT="${cfg.vaultPath}"
        mkdir -p "$VAULT"

        if [ ! -d "$VAULT/.git" ]; then
          ${pkgs.git}/bin/git -C "$VAULT" init
          ${pkgs.git}/bin/git -C "$VAULT" config user.email "${cfg.gitEmail}"
          ${pkgs.git}/bin/git -C "$VAULT" config user.name "Hermes Agent"
        fi

        mkdir -p "$VAULT/memories"
        mkdir -p "$VAULT/skills/core/vault-git"
        mkdir -p "$VAULT/skills/core/nix-environments"
        mkdir -p "$VAULT/skills/core/nix-config-pr"
        mkdir -p "$VAULT/environments"
        mkdir -p "$VAULT/requests"
        mkdir -p "$VAULT/notes"

        # seed <relative-path> <nix-store-source>
        # Copies only if the destination doesn't already exist.
        seed() {
          local dest="$VAULT/$1"
          [ -f "$dest" ] || cp "$2" "$dest"
        }

        seed "SOUL.md"                             "${initialSoul}"
        seed "memories/MEMORY.md"                  ${pkgs.writeText "MEMORY.md" "# Agent Memory\n\n<!-- Hermes writes here. -->\n"}
        seed "memories/USER.md"                    ${pkgs.writeText "USER.md" "# User Profile\n\n<!-- Hermes writes here as it learns your preferences. -->\n"}
        seed "skills/core/vault-git/SKILL.md"      "${skillVaultGit}"
        seed "skills/core/nix-environments/SKILL.md" "${skillNixEnvironments}"
        seed "skills/core/nix-config-pr/SKILL.md"  "${skillNixConfigPr}"
        seed ".gitignore"                           ${pkgs.writeText "hermes-gitignore" ''
          state.db
          state.db-shm
          state.db-wal
          sandboxes/
          .obsidian/workspace.json
          .obsidian/workspace-mobile.json
        ''}

        if ! ${pkgs.git}/bin/git -C "$VAULT" rev-parse HEAD >/dev/null 2>&1; then
          ${pkgs.git}/bin/git -C "$VAULT" add -A
          ${pkgs.git}/bin/git -C "$VAULT" commit -m "init: hermes vault"
        fi

        # Ensure vault is owned by the normal user, not root.
        # The parent /data path is NFS-backed; chown only the vault subtree.
        chown -R ${cfg.vaultOwner}:${cfg.vaultOwner} "$VAULT"
      '';
      deps = [ "users" "groups" "hermesAgentSshKey" ];
    };

    # ---------------------------------------------------------------------------
    # Hermes Agent container
    #
    # --network=host: reaches LiteLLM on 127.0.0.1:4000 and the SSH server
    # on 127.0.0.1:22 (executor user) without extra port mapping.
    # ---------------------------------------------------------------------------
    virtualisation.oci-containers.containers.hermes-agent = {
      image = cfg.image;
      volumes = [
        "${cfg.vaultPath}:/hermes-home"
        "${cfg.nixConfigPath}:/nix-config:ro"
        "/var/lib/hermes-agent/ssh:/root/.ssh:ro"
      ];
      environment = {
        HERMES_HOME        = "/hermes-home";
        HERMES_MODEL_BASE  = cfg.inferenceUrl;
        GIT_AUTHOR_EMAIL   = cfg.gitEmail;
        GIT_AUTHOR_NAME    = "Hermes Agent";
        GIT_COMMITTER_EMAIL = cfg.gitEmail;
        GIT_COMMITTER_NAME = "Hermes Agent";
      };
      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;
      extraOptions = [ "--network=host" ];
    };

    # Wait for LiteLLM (systemd service) before starting the agent container.
    systemd.services."docker-hermes-agent" = {
      after = [ "litellm.service" ];
      wants = [ "litellm.service" ];
    };
  };
}
