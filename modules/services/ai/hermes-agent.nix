{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.hermes-agent;

  # ---------------------------------------------------------------------------
  # Cron job seed script
  # Manages a "nix-managed" subset of ~/.hermes/cron/jobs.json.
  # Idempotent: removes stale nix-managed entries, inserts current ones.
  # Does not touch user-created jobs (no "nix-managed" tag).
  # ---------------------------------------------------------------------------
  allScheduledTasks = cfg.scheduledTasks
    ++ optional cfg.digest.enable {
        name  = "nix-morning-digest";
        cron  = cfg.digest.cron;
        prompt = ''
          Post a morning digest to the Matrix ${
            if cfg.matrixNotificationRoom != null
            then "notification room"
            else "home room"
          }. Include:
          1. Any services that restarted or failed overnight (check journalctl -p err --since yesterday)
          2. ZFS pool health summary (zpool status -x)
          3. Disk usage on / and /data if above 80%
          4. A one-line note if anything needs attention, otherwise just "All clear."
          Keep it short — bullet points, no preamble.
        '';
      }
    ++ optional cfg.nixUpdateSummary.enable {
        name  = "nix-weekly-update-summary";
        cron  = cfg.nixUpdateSummary.cron;
        prompt = ''
          Check the nix-config repo for any pending flake input updates.
          Run: cd /nix-config && git pull && nix flake metadata --json
          Summarise which inputs are behind HEAD (if any), what major version
          changes are implied, and whether anything looks risky. Post to Matrix.
        '';
      }
    ++ optional cfg.nightlyAnomalyScan.enable {
        name  = "nix-nightly-anomaly-scan";
        cron  = cfg.nightlyAnomalyScan.cron;
        prompt = ''
          Silent anomaly scan — only post to Matrix if something is wrong.
          Check:
          - journalctl -p err --since "2 hours ago" (filter noise like avahi/systemd-resolved)
          ${optionalString (cfg.nightlyAnomalyScan.services != [])
            "- systemctl is-active ${concatStringsSep " " cfg.nightlyAnomalyScan.services}"}
          ${optionalString (cfg.nightlyAnomalyScan.pools != [])
            "- zpool status ${concatStringsSep " " cfg.nightlyAnomalyScan.pools}"}
          If everything is healthy, do nothing (no message). Only speak up
          when there is a real problem.
        '';
      }
    ++ optional cfg.monthlyVaultMaintenance.enable {
        name  = "nix-monthly-vault-maintenance";
        cron  = cfg.monthlyVaultMaintenance.cron;
        prompt = ''
          Monthly vault maintenance pass:
          1. Review memories/ — merge duplicates, mark stale entries for removal
          2. Review skills/ — note any skills that haven't been used in 30 days
          3. Commit any changes to the vault git repo
          4. If vault has a remote, push.
          Post a one-line summary to Matrix when done.
        '';
      }
    ++ optional (cfg.vaultwardenAudit.enable) {
        name  = "nix-monthly-password-audit";
        cron  = cfg.vaultwardenAudit.cron;
        prompt = ''
          Vaultwarden audit pass. Using the Vaultwarden API at ${cfg.vaultwardenAudit.apiUrl}:
          1. List items and flag any with passwords older than 180 days
          2. Flag any HTTP (non-HTTPS) URIs
          3. Flag any entries with no password (username-only)
          Do NOT read or expose any passwords. Post a summary count to Matrix
          (e.g. "3 stale, 1 HTTP URI, 0 empty"). If nothing to flag, skip.
        '';
      }
    ++ optional cfg.weeklyStorageReport.enable {
        name  = "nix-weekly-storage-report";
        cron  = cfg.weeklyStorageReport.cron;
        prompt = ''
          Weekly storage report. Run:
          - df -h (highlight anything above 75%)
          - zfs list -o name,used,avail,refer -s used | head -20
          - du -sh /data/tristonyoder/home/vaults/hermes-brain (vault size)
          Post a compact table to Matrix. Warn if any dataset is above 80%.
        '';
      };

  # Python script that seeds/reconciles nix-managed cron jobs in jobs.json
  cronSeedScript = pkgs.writeText "hermes-cron-seed.py" ''
    #!/usr/bin/env python3
    """
    Seed nix-declared cron jobs into ~/.hermes/cron/jobs.json.
    Idempotent: tagged entries are replaced on every activation.
    User-created jobs (no "nix-managed" tag) are never touched.
    """
    import json, os, sys, uuid, tempfile
    from pathlib import Path
    from datetime import datetime, timezone

    CRON_DIR = Path(os.environ["HERMES_HOME"]) / "cron"
    JOBS_FILE = CRON_DIR / "jobs.json"
    CRON_DIR.mkdir(parents=True, exist_ok=True)

    declared = json.loads(sys.argv[1])

    # Load existing jobs (may not exist yet)
    try:
        jobs = json.loads(JOBS_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        jobs = []

    # Remove stale nix-managed entries
    jobs = [j for j in jobs if "nix-managed" not in j.get("tags", [])]

    # Add current nix-managed entries
    now = datetime.now(timezone.utc).isoformat()
    for task in declared:
        # Stable ID derived from name so activation is truly idempotent
        stable_id = "nix-" + uuid.uuid5(uuid.NAMESPACE_DNS, task["name"]).hex[:12]
        jobs.append({
            "id":           stable_id,
            "name":         task["name"],
            "prompt":       task["prompt"],
            "schedule":     {"kind": "cron", "expr": task["cron"]},
            "enabled":      True,
            "state":        "scheduled",
            "tags":         ["nix-managed"],
            "created_at":   now,
            "last_run_at":  None,
            "run_count":    0,
            "next_run_at":  None,
        })

    # Atomic write
    tmp = JOBS_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(jobs, indent=2))
    tmp.replace(JOBS_FILE)
    print(f"hermes-cron-seed: {len([j for j in jobs if 'nix-managed' in j.get('tags',[])])} nix-managed jobs written")
  '';

in
{
  options.modules.services.ai.hermes-agent = {
    enable = mkEnableOption "Hermes Agent (NousResearch)";

    # ── Core ────────────────────────────────────────────────────────────────

    model = mkOption {
      type = types.str;
      default = "anthropic/claude-opus-4-8";
      description = "Default LLM model. Should be a LiteLLM-routed name or direct provider string.";
    };

    inferenceUrl = mkOption {
      type = types.nullOr types.str;
      default = "http://127.0.0.1:${toString config.modules.services.ai.litellm.port}";
      description = "Base URL for the LiteLLM proxy. Null uses provider URLs directly.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Agenix-decrypted environment file. Must contain ANTHROPIC_API_KEY and LITELLM_MASTER_KEY.";
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

    # ── Identity ─────────────────────────────────────────────────────────────

    soul = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SOUL.md content (persona). Written to HERMES_HOME at activation via activation script. Null uses hermes's built-in default.";
    };

    agentsMd = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "AGENTS.md content installed into the hermes working directory. Loaded as project context on every session.";
    };

    # ── Matrix ───────────────────────────────────────────────────────────────

    matrixNotificationRoom = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Matrix room ID for proactive notifications (digests, alerts, cron output). Falls back to homeRoom if null.";
    };

    # ── Vault ────────────────────────────────────────────────────────────────

    vaultGitRemote = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Git remote URL for the hermes vault. Written to vault/.git/config at activation. Enables the vault-git skill to push off-host.";
    };

    # ── Users ────────────────────────────────────────────────────────────────

    hostUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users who get a ~/.hermes symlink to the service state dir (for host-CLI parity with the container).";
    };

    # ── Executor ─────────────────────────────────────────────────────────────

    executorPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Additional packages available to the hermes-executor user (and therefore to hermes via SSH).";
    };

    # ── Scheduled tasks ──────────────────────────────────────────────────────

    scheduledTasks = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name   = mkOption { type = types.str; description = "Unique name for this task (used as stable job ID)."; };
          cron   = mkOption { type = types.str; description = "Cron expression, e.g. '0 8 * * *'."; };
          prompt = mkOption { type = types.str; description = "Prompt hermes runs on schedule."; };
        };
      });
      default = [];
      description = "User-defined scheduled tasks written into hermes's cron scheduler at activation.";
    };

    digest = {
      enable = mkOption { type = types.bool; default = true;
        description = "Morning digest: service health, ZFS, disk usage. Posts to Matrix."; };
      cron   = mkOption { type = types.str; default = "0 8 * * *";
        description = "Cron schedule for the morning digest."; };
    };

    nixUpdateSummary = {
      enable = mkOption { type = types.bool; default = true;
        description = "Weekly nix flake update summary. Checks input staleness, posts to Matrix."; };
      cron   = mkOption { type = types.str; default = "0 9 * * 1";
        description = "Cron schedule (default: Monday 9am)."; };
    };

    nightlyAnomalyScan = {
      enable    = mkOption { type = types.bool; default = true;
        description = "Nightly silent anomaly scan. Posts to Matrix only when something is wrong."; };
      cron      = mkOption { type = types.str; default = "0 2 * * *";
        description = "Cron schedule (default: 2am daily)."; };
      services  = mkOption { type = types.listOf types.str; default = [];
        description = "Systemd services to check in the nightly scan."; };
      pools     = mkOption { type = types.listOf types.str; default = [];
        description = "ZFS pools to check in the nightly scan."; };
    };

    monthlyVaultMaintenance = {
      enable = mkOption { type = types.bool; default = true;
        description = "Monthly vault housekeeping: dedup memories, flag stale skills, push to remote."; };
      cron   = mkOption { type = types.str; default = "0 10 1 * *";
        description = "Cron schedule (default: 1st of month, 10am)."; };
    };

    vaultwardenAudit = {
      enable  = mkOption { type = types.bool; default = false;
        description = "Monthly Vaultwarden audit: stale passwords, HTTP URIs, empty entries."; };
      cron    = mkOption { type = types.str; default = "0 10 1 * *";
        description = "Cron schedule (default: 1st of month, 10am)."; };
      apiUrl  = mkOption { type = types.str; default = "http://localhost:8222";
        description = "Vaultwarden API base URL."; };
    };

    weeklyStorageReport = {
      enable = mkOption { type = types.bool; default = true;
        description = "Weekly storage report: df, ZFS dataset sizes, vault size. Posts to Matrix."; };
      cron   = mkOption { type = types.str; default = "0 9 * * 6";
        description = "Cron schedule (default: Saturday 9am)."; };
    };

    # ── Integrations ─────────────────────────────────────────────────────────

    homelabMcp = {
      enable  = mkOption { type = types.bool; default = true;
        description = "Register the hermes-homelab-mcp server so hermes can query service health, ZFS, disk, and Tailscale status via structured tool calls."; };
      port    = mkOption { type = types.port; default = 7830;
        description = "Port the homelab MCP SSE server listens on (localhost only)."; };
      allowRestarts = mkOption { type = types.bool; default = false;
        description = "Expose a restart_service tool. Each call requires Matrix confirmation before executing (enforced by the skill, not the tool itself)."; };
    };

    immich = {
      enable      = mkOption { type = types.bool; default = false;
        description = "Wire IMMICH_API_URL and IMMICH_API_KEY_ENV into hermes environment for Immich API access."; };
      apiUrl      = mkOption { type = types.str; default = "http://localhost:2283";
        description = "Immich API base URL."; };
      apiKeyEnvVar = mkOption { type = types.str; default = "IMMICH_API_KEY";
        description = "Name of the env var holding the Immich API key (sourced from environmentFile)."; };
    };

    n8n = {
      enable      = mkOption { type = types.bool; default = false;
        description = "Wire N8N_BASE_URL into hermes environment so the executor can trigger n8n workflows via webhook."; };
      baseUrl     = mkOption { type = types.str; default = "http://localhost:5678";
        description = "n8n base URL."; };
      apiKeyEnvVar = mkOption { type = types.str; default = "N8N_API_KEY";
        description = "Name of the env var holding the n8n API key."; };
    };

    # ── Passthroughs ─────────────────────────────────────────────────────────

    mcpServers = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional MCP servers merged into services.hermes-agent.mcpServers.";
    };

    extraPlugins = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Extra plugins passed to services.hermes-agent.extraPlugins.";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = "Arbitrary settings merged into services.hermes-agent.settings.";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

    # ── Upstream service ──────────────────────────────────────────────────────

    services.hermes-agent = {
      enable            = true;
      addToSystemPackages = true;

      # Use optionalAttrs (not mkIf) — upstream serializes mkIf into dicts and
      # runtime_provider.py calls .strip() on those → AttributeError.
      settings = {
        model = { default = cfg.model; provider = "custom:litellm-proxy"; }
          // optionalAttrs (cfg.inferenceUrl != null) { base_url = cfg.inferenceUrl; };
      } // optionalAttrs (cfg.inferenceUrl != null) {
        providers.litellm-proxy = {
          api     = cfg.inferenceUrl;
          key_env = "LITELLM_MASTER_KEY";
        };
      } // cfg.extraSettings;

      environmentFiles = optional (cfg.environmentFile != null) cfg.environmentFile;

      environment = {}
        // optionalAttrs (cfg.homeRoom != null)               { MATRIX_HOME_ROOM         = cfg.homeRoom; }
        // optionalAttrs (cfg.matrixNotificationRoom != null)  { MATRIX_NOTIFICATION_ROOM = cfg.matrixNotificationRoom; }
        // optionalAttrs cfg.immich.enable {
             IMMICH_API_URL     = cfg.immich.apiUrl;
             IMMICH_API_KEY_ENV = cfg.immich.apiKeyEnvVar;
           }
        // optionalAttrs cfg.n8n.enable {
             N8N_BASE_URL     = cfg.n8n.baseUrl;
             N8N_API_KEY_ENV  = cfg.n8n.apiKeyEnvVar;
           };

      documents = {}
        // optionalAttrs (cfg.agentsMd != null) { "AGENTS.md" = cfg.agentsMd; };

      extraDependencyGroups = [ "matrix" ];

      container = mkIf cfg.containerMode {
        enable       = true;
        backend      = "docker";
        extraVolumes = cfg.extraVolumes;
        hostUsers    = cfg.hostUsers;
      };

      extraPlugins = cfg.extraPlugins;

      mcpServers = cfg.mcpServers
        // optionalAttrs (cfg.homelabMcp.enable
            && config.modules.services.ai.hermes-homelab-mcp.enable) {
          homelab.url = "http://localhost:${toString cfg.homelabMcp.port}/sse";
        };
    };

    # ── Executor packages ─────────────────────────────────────────────────────

    users.users.hermes-executor.packages = mkIf (cfg.executorPackages != [])
      cfg.executorPackages;

    # ── SOUL.md → HERMES_HOME ─────────────────────────────────────────────────
    # load_soul_md() reads from HERMES_HOME/SOUL.md, not workingDirectory.
    # documents installs to workingDirectory — wrong path, silent no-op.

    system.activationScripts.hermesAgentSoul = mkIf (cfg.soul != null) {
      text = ''
        install -o hermes-agent -g hermes-agent -m 0660 \
          ${pkgs.writeText "hermes-SOUL.md" cfg.soul} \
          /var/lib/hermes-agent/.hermes/SOUL.md
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };

    # ── Vault git remote ──────────────────────────────────────────────────────

    system.activationScripts.hermesAgentVaultRemote = mkIf (cfg.vaultGitRemote != null) {
      text = ''
        VAULT=/var/lib/hermes-agent/.hermes
        if [ -d "$VAULT/.git" ]; then
          if ${pkgs.git}/bin/git -C "$VAULT" remote get-url origin >/dev/null 2>&1; then
            ${pkgs.git}/bin/git -C "$VAULT" remote set-url origin ${escapeShellArg cfg.vaultGitRemote}
          else
            ${pkgs.git}/bin/git -C "$VAULT" remote add origin ${escapeShellArg cfg.vaultGitRemote}
          fi
        fi
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };

    # ── Cron job seeding ──────────────────────────────────────────────────────

    system.activationScripts.hermesAgentCronJobs = mkIf (allScheduledTasks != []) {
      text = ''
        HERMES_HOME=/var/lib/hermes-agent/.hermes \
          ${pkgs.python3}/bin/python3 ${cronSeedScript} \
          ${escapeShellArg (builtins.toJSON (map (t: {
            inherit (t) name cron prompt;
          }) allScheduledTasks))}
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };

    # ── Homelab MCP: wire port when our module is enabled ────────────────────

    modules.services.ai.hermes-homelab-mcp = mkIf cfg.homelabMcp.enable {
      enable        = true;
      port          = cfg.homelabMcp.port;
      allowRestarts = cfg.homelabMcp.allowRestarts;
    };
  };
}
