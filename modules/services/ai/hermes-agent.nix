{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.hermes-agent;

  # ---------------------------------------------------------------------------
  # Vault skill definitions — seeded into HERMES_HOME/skills/ at activation.
  # Written only once (existence check); the agent can improve them over time.
  # ---------------------------------------------------------------------------

  skillRelationshipCrm = ''
    ---
    name: relationship-crm
    description: Track and maintain relationships using vault memories — birthdays, last contact, follow-ups
    version: 1.0.0
    category: life
    tags: [relationships, memory, crm]
    always_active: false
    ---

    ## Purpose

    Keep a lightweight CRM in vault memories. No external service — everything
    lives in `$HERMES_HOME/memories/people/`. Commit after every write (vault-git skill).

    ## Memory file format

    Path: `memories/people/<firstname-lastname>.md`

    ```markdown
    # Jane Smith

    **Birthday:** 1990-03-15
    **Last contact:** 2025-11-20
    **How we know:** College friend
    **Location:** Austin, TX

    ## Notes
    - Loves hiking, has two dogs
    - Working on a startup in climate tech

    ## Follow-ups
    - [ ] Send her the Patagonia recommendation she asked about
    ```

    ## Triggers

    - When you have a conversation that mentions a person by name and something worth remembering
    - When the user says "remember that [person]..."
    - After the weekly relationship nudge task fires

    ## Weekly nudge (automated)

    The `nix-relationship-nudge` cron job scans all people files and:
    1. Flags anyone with `Last contact` older than 60 days
    2. Flags birthdays in the next 14 days
    3. Posts a compact list to Matrix — name, days since contact, any upcoming birthday

    ## Commands for the agent

    ```bash
    # List all people files
    ls $HERMES_HOME/memories/people/

    # Find people not contacted recently
    grep -l "Last contact:" $HERMES_HOME/memories/people/*.md | \
      xargs grep "Last contact:" | sort -t: -k3

    # Upcoming birthdays (next 14 days)
    python3 -c "
    import os, re
    from datetime import date, timedelta
    today = date.today()
    window_end = today + timedelta(days=14)
    people_dir = os.path.expandvars('\$HERMES_HOME/memories/people')
    if not os.path.isdir(people_dir): exit()
    for f in os.listdir(people_dir):
        if not f.endswith('.md'): continue
        text = open(os.path.join(people_dir, f)).read()
        m = re.search(r'Birthday.*?(\d{4}-\d{2}-\d{2})', text)
        if not m: continue
        bd = date.fromisoformat(m.group(1))
        this_year = bd.replace(year=today.year)
        if this_year < today: this_year = bd.replace(year=today.year+1)
        if this_year <= window_end:
            days = (this_year - today).days
            name = f.replace('-', ' ').replace('.md', '').title()
            print(f'{days}d: {name} ({this_year})')
    "
    ```
  '';

  skillFocusMode = ''
    ---
    name: focus-mode
    description: Enter a deep work session — block distractions, protect calendar time, set Matrix away status
    version: 1.0.0
    category: productivity
    tags: [focus, calendar, productivity]
    always_active: false
    ---

    ## Purpose

    When the user asks to "focus" or "deep work", run a structured focus session:
    1. Post an away message to Matrix home room
    2. Block time on calendar (via calendar MCP if available)
    3. Set a timer
    4. Check in when done

    ## Trigger phrases

    - "focus mode [N] minutes/hours"
    - "deep work session"
    - "I need to focus for..."
    - "block off [time] for..."

    ## Protocol

    ```
    1. Confirm duration (default: ${toString cfg.focusMode.defaultDuration} minutes)
    2. Post to Matrix home room:
       "🎯 Focus mode: [task description]. Back at [time]. DMs OK for urgent."
    3. Create calendar block if calendar MCP available
    4. Wait duration, then post:
       "⏰ Focus session complete. How did it go?"
    5. Save a brief note to vault: date, task, duration, outcome
    ```

    ## Calendar block

    Only if the user has a calendar MCP connected. Use "Focus: [task]" as title,
    set as busy, private.

    ## Session log

    Save to `$HERMES_HOME/memories/focus-sessions.md` after each session.
    Review weekly to notice patterns (best times, common interruptions).
  '';

  skillWeeklyReview = ''
    ---
    name: weekly-review
    description: Structured Friday review ritual — reflect on the week, set intentions for next
    version: 1.0.0
    category: productivity
    tags: [review, planning, ritual]
    always_active: false
    ---

    ## Purpose

    Run every Friday at ${cfg.weeklyReview.cron} via the nix-weekly-review cron job.
    Aggregate data from across the week, reflect, plan ahead.

    ## Review structure

    Post to Matrix notification room with this format:

    ```
    📋 Week of [date] — Review

    **This week:**
    - [3-5 bullet points of notable events/completions from calendar + memory]

    **Finances (week):**
    - Total spent: $X  |  On track / At risk / Over
    - Notable: [largest transaction or category spike]

    **Infrastructure:**
    - Any incidents? Services that needed attention?

    **Focus sessions:** X this week, avg Y minutes

    **Relationships:** [Anyone to reach out to?]

    ---
    What's one thing to carry into next week?
    ```

    ## Data sources

    Pull from (use MCP tools as available):
    - Calendar: events from Mon–Fri
    - actual_spending_summary / actual_budget_status for the week
    - Vault memories written this week: `git -C $HERMES_HOME log --since="7 days ago" --oneline`
    - Focus session log
    - Homelab anomaly scan results (nix-nightly-anomaly-scan output)

    ## After the review

    Wait for the user's reply (if any), then:
    1. Save their answer as a vault memory entry
    2. Commit to vault git
  '';

  skillImmichAlbums = ''
    ---
    name: immich-albums
    description: Create and manage Immich photo albums via natural language
    version: 1.0.0
    category: media
    tags: [immich, photos, albums]
    always_active: false
    ---

    ## Purpose

    Create smart Immich albums from conversational requests using MCP tools.

    ## Trigger phrases

    - "make an album of..."
    - "create a photo album..."
    - "find photos of/from..."
    - "put together pictures of..."

    ## Workflow

    1. Use `immich_search` to find matching assets (date range, city, smart query)
    2. Show a preview: "Found X photos — [date range], [cities]. Create album '[name]'?"
    3. On confirmation: call `immich_create_album` with collected asset IDs
    4. Reply with the album link

    ## Search strategies

    - By date range: use `date_from` / `date_to`
    - By location: use `city` parameter
    - By content: use `query` for smart/semantic search
    - Combine: search by date first, then filter by city

    ## Album naming

    Suggest a name based on the request:
    - "Scotland trip August 2024" → dates + inferred location
    - "Dogs" → descriptor only
    Ask the user to confirm or rename before creating.
  '';

  skillBudgetReview = ''
    ---
    name: budget-review
    description: Query and interpret Actual Budget data — spending trends, budget adherence, alerts
    version: 1.0.0
    category: finance
    tags: [budget, finance, actual]
    always_active: false
    ---

    ## Purpose

    Surface financial awareness without reading raw numbers at the user —
    interpret the data and present it as useful insights.

    ## MCP tools available

    - `actual_spending_summary(month?)` — totals by category
    - `actual_budget_status(month?)` — over/under per category
    - `actual_recent_transactions(days?, limit?)` — recent transactions

    ## Response style

    - Lead with the headline: "On track", "One category over", "Three categories over"
    - Show over-budget categories prominently
    - Call out any single transaction > $${toString cfg.actualBudget.alertThreshold}
    - Skip categories that are well under (< 50%) unless asked

    ## Alert thresholds

    - Any category > 100% of budget → immediate flag
    - Any single transaction > $${toString cfg.actualBudget.alertThreshold} → mention in digest
    - Month-to-date total spend > 90% of monthly income estimate → warning

    ## Monthly report (automated)

    The `nix-monthly-budget-report` cron job runs on the last day of each month
    and posts a full breakdown to Matrix.
  '';

  skillNotionTasks = ''
    ---
    name: notion-tasks
    description: Sync tasks with Notion — capture from conversation, update status, audit stale items
    version: 1.0.0
    category: productivity
    tags: [notion, tasks, productivity]
    always_active: false
    ---

    ## Purpose

    Use the Notion MCP to keep tasks in sync without opening Notion manually.

    ## Capture flow

    When user says "add task: [thing]" or "remind me to..." or "put in Notion...":
    1. Create a page in the designated tasks database
    2. Set title, due date if mentioned, priority if mentioned
    3. Confirm: "Added '[task]' to Notion."

    ## Status queries

    "What do I have due this week?" → query Notion tasks database,
    filter by due date this week, sort by priority, post compact list.

    ## Stale task audit (automated)

    The `nix-notion-stale-audit` cron job runs weekly and:
    1. Finds tasks open > 30 days with no update
    2. Posts list to Matrix: "X stale tasks in Notion — worth a review?"
    3. Does NOT close or modify them without explicit instruction

    ## Important

    Never mark tasks complete without explicit user confirmation.
    Never delete Notion pages.
  '';

  # ---------------------------------------------------------------------------
  # Skill seeding activation script
  # ---------------------------------------------------------------------------
  skillSeedScript = pkgs.writeText "hermes-skill-seed.py" ''
    #!/usr/bin/env python3
    """Seed life management skills into HERMES_HOME/skills/. Never overwrites."""
    import json, os, sys
    from pathlib import Path

    home   = Path(os.environ["HERMES_HOME"])
    skills = json.loads(sys.argv[1])

    for skill in skills:
        category = skill["category"]
        name     = skill["name"]
        content  = skill["content"]
        dest     = home / "skills" / category / name / "SKILL.md"
        if dest.exists():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
        print(f"hermes-skill-seed: seeded {category}/{name}")
  '';

  # All skills to seed, only those whose feature flag is enabled
  skillsToSeed = []
    ++ optional cfg.relationshipCrm.enable {
        category = "life"; name = "relationship-crm"; content = skillRelationshipCrm; }
    ++ optional cfg.focusMode.enable {
        category = "productivity"; name = "focus-mode"; content = skillFocusMode; }
    ++ optional cfg.weeklyReview.enable {
        category = "productivity"; name = "weekly-review"; content = skillWeeklyReview; }
    ++ optional cfg.immich.enable {
        category = "media"; name = "immich-albums"; content = skillImmichAlbums; }
    ++ optional cfg.actualBudget.enable {
        category = "finance"; name = "budget-review"; content = skillBudgetReview; }
    ++ optional cfg.notionSync.enable {
        category = "productivity"; name = "notion-tasks"; content = skillNotionTasks; }
    ++ cfg.extraSkills;

  # ---------------------------------------------------------------------------
  # Scheduled tasks — built-in + user-defined, collapsed into one seed
  # ---------------------------------------------------------------------------

  allScheduledTasks = cfg.scheduledTasks

    ++ optional cfg.digest.enable {
        name  = "nix-morning-digest";
        cron  = cfg.digest.cron;
        prompt = ''
          Post a morning briefing to Matrix. Pull from every available source:

          📅 CALENDAR (if calendar MCP available):
          - Events today and tomorrow

          ☀️ WEATHER:
          - Use the homelab MCP weather tool

          💰 FINANCES (if Actual Budget connected):
          - Use actual_budget_status for current month — one line: on track / any over-budget categories

          🖼️ ON THIS DAY:
          - Use immich_on_this_day — list photos from this date in past years (max 3)

          📺 MEDIA:
          - Use jellyseerr_requests with status=available — any requests that just became available?

          🖥️ INFRASTRUCTURE:
          - Use zfs_pool_status — only mention if not "all pools healthy"
          - Use disk_usage with warn_above=80 — only mention if triggered

          Format: short, scannable. Skip any section where nothing notable is happening.
          Total length: under 20 lines.
        '';
      }

    ++ optional cfg.nixUpdateSummary.enable {
        name  = "nix-weekly-update-summary";
        cron  = cfg.nixUpdateSummary.cron;
        prompt = ''
          Weekly nix flake staleness check. Steps:
          1. Use nix_flake_info MCP tool to see current input revisions
          2. SSH to executor and run: cd /nix-config && git pull && nix flake metadata --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); [print(k, v.get('lastModified','?')) for k,v in d.get('locks',{}).get('nodes',{}).items() if k!='root']"
          3. Compare — flag any input more than 30 days stale
          4. If anything is stale, post summary to Matrix with the input names
          5. If all fresh, skip (no message)
        '';
      }

    ++ optional cfg.nightlyAnomalyScan.enable {
        name  = "nix-nightly-anomaly-scan";
        cron  = cfg.nightlyAnomalyScan.cron;
        prompt = ''
          Silent nightly scan — only post to Matrix if something is ACTUALLY wrong.

          Check via homelab MCP:
          - service_logs for each of: ${concatStringsSep ", " cfg.nightlyAnomalyScan.services} — errors in last 2 hours
          ${optionalString (cfg.nightlyAnomalyScan.pools != [])
            "- zfs_pool_status for pools: ${concatStringsSep ", " cfg.nightlyAnomalyScan.pools}"}
          - disk_usage with warn_above=85

          If everything is healthy → do nothing, post nothing.
          Only speak when there is a real problem worth waking someone up for.
          One short Matrix message max. Skip systemd noise (avahi, resolved).
        '';
      }

    ++ optional cfg.weeklyReview.enable {
        name  = "nix-weekly-review";
        cron  = cfg.weeklyReview.cron;
        prompt = ''
          Friday weekly review. Follow the weekly-review skill protocol.
          Pull data from all available MCP tools and vault git log.
          Post the structured review to Matrix, then ask the reflection question.
          Save the user's response (if any within 1 hour) as a vault memory.
        '';
      }

    ++ optional cfg.monthlyVaultMaintenance.enable {
        name  = "nix-monthly-vault-maintenance";
        cron  = cfg.monthlyVaultMaintenance.cron;
        prompt = ''
          Monthly vault housekeeping:
          1. Review memories/ — identify near-duplicate entries, merge them
          2. Review skills/ — list skills not referenced in recent sessions
          3. Compact the memories index (MEMORY.md) if it's grown stale
          4. Commit all changes: git -C $HERMES_HOME add -A && git -C $HERMES_HOME commit -m "maintenance: monthly vault cleanup"
          5. Push if remote configured
          6. Post one-line summary to Matrix
        '';
      }

    ++ optional (cfg.actualBudget.enable && cfg.actualBudget.monthlyReport) {
        name  = "nix-monthly-budget-report";
        cron  = cfg.actualBudget.monthlyReportCron;
        prompt = ''
          End-of-month budget report. Use the budget-review skill and:
          1. actual_spending_summary for the month just ended
          2. actual_budget_status — call out any over-budget categories
          3. actual_recent_transactions for last 7 days — any large items?
          Post a structured breakdown to Matrix.
          Save a summary to vault: memories/finances/YYYY-MM.md
        '';
      }

    ++ optional (cfg.actualBudget.enable && cfg.actualBudget.weeklyReport) {
        name  = "nix-weekly-budget-pulse";
        cron  = cfg.actualBudget.weeklyReportCron;
        prompt = ''
          Weekly budget pulse check. Use actual_budget_status for current month.
          If all categories are under 80% of budget with more than a week left → skip, post nothing.
          If any category is over budget or approaching → post a brief warning to Matrix.
          Keep it to 3 lines max.
        '';
      }

    ++ optional cfg.immichOnThisDay.enable {
        name  = "nix-immich-on-this-day";
        cron  = cfg.immichOnThisDay.cron;
        prompt = ''
          Daily memory prompt. Use immich_on_this_day MCP tool.
          If photos found: post to Matrix with dates and thumbnail links.
            Format: "📸 On this day: [year] — [city if available]"
            List up to 4 photos with year and location.
          If no photos: skip, post nothing.
        '';
      }

    ++ optional (cfg.relationshipCrm.enable && cfg.relationshipCrm.weeklyNudge) {
        name  = "nix-relationship-nudge";
        cron  = cfg.relationshipCrm.nudgeCron;
        prompt = ''
          Weekly relationship check. Follow the relationship-crm skill protocol:
          1. Scan memories/people/ for anyone not contacted in >60 days
          2. Check for birthdays in the next 14 days
          3. If anything found: post a compact list to Matrix
             Format: "👋 [Name] — [X] days since contact" or "🎂 [Name] — birthday in [N] days"
          4. If nothing: skip, post nothing.
        '';
      }

    ++ optional (cfg.notionSync.enable && cfg.notionSync.weeklyTaskAudit) {
        name  = "nix-notion-stale-audit";
        cron  = cfg.notionSync.auditCron;
        prompt = ''
          Weekly Notion task audit. Follow the notion-tasks skill protocol:
          Use the Notion MCP to find tasks open longer than 30 days with no recent update.
          If stale tasks found: post count + titles to Matrix.
          If none: skip.
        '';
      }

    ++ optional (cfg.vaultwardenAudit.enable) {
        name  = "nix-monthly-password-audit";
        cron  = cfg.vaultwardenAudit.cron;
        prompt = ''
          Monthly Vaultwarden hygiene check. Use the vaultwarden_health MCP tool.
          Also use executor SSH to run Bitwarden CLI if available:
            bw list items --session $BW_SESSION 2>/dev/null | python3 -c "..."
          Report to Matrix:
          - Count of passwords older than 180 days (do NOT show the passwords)
          - Count of items with HTTP (non-HTTPS) URIs
          - Count of items with no password
          - Overall: "X items need attention" or "All clear"
        '';
      }

    ++ optional cfg.weeklyStorageReport.enable {
        name  = "nix-weekly-storage-report";
        cron  = cfg.weeklyStorageReport.cron;
        prompt = ''
          Weekly storage report. Use MCP tools:
          - disk_usage — show filesystems above 60%
          - zfs_list with sort=used and limit=15
          Post a compact table to Matrix. Highlight anything above 80% in bold.
        '';
      };

in
{
  options.modules.services.ai.hermes-agent = {
    enable = mkEnableOption "Hermes Agent (NousResearch)";

    # ── Core ─────────────────────────────────────────────────────────────────

    model = mkOption {
      type = types.str;
      default = "anthropic/claude-opus-4-8";
      description = "Default LLM model. Should be a LiteLLM-routed name or direct provider string.";
    };

    inferenceUrl = mkOption {
      type = types.nullOr types.str;
      default = "http://127.0.0.1:${toString config.modules.services.ai.litellm.port}";
      description = "LiteLLM proxy base URL. Null uses provider URLs directly.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Agenix-decrypted env file. Must contain ANTHROPIC_API_KEY and LITELLM_MASTER_KEY.";
    };

    containerMode = mkOption {
      type = types.bool;
      default = true;
      description = "Run Hermes in a Docker container.";
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

    # ── Identity ──────────────────────────────────────────────────────────────

    soul = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SOUL.md content. Written to HERMES_HOME at activation. Null uses hermes's built-in default.";
    };

    agentsMd = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "AGENTS.md content installed into the hermes working directory (project context, loaded every session).";
    };

    # ── Matrix ────────────────────────────────────────────────────────────────

    matrixNotificationRoom = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Matrix room ID for proactive notifications (digests, alerts, cron output). Falls back to homeRoom if null.";
    };

    # ── Vault ─────────────────────────────────────────────────────────────────

    vaultGitRemote = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Git remote URL for the hermes vault. Written at activation.";
    };

    # ── Users / executor ──────────────────────────────────────────────────────

    hostUsers = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Users who get a ~/.hermes symlink to the service state dir.";
    };

    executorPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Extra packages available to hermes-executor user.";
    };

    # ── Built-in scheduled behaviors ──────────────────────────────────────────

    scheduledTasks = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name   = mkOption { type = types.str; };
          cron   = mkOption { type = types.str; };
          prompt = mkOption { type = types.str; };
        };
      });
      default = [];
      description = "User-defined scheduled tasks added to hermes cron.";
    };

    digest = {
      enable = mkOption { type = types.bool; default = true;
        description = "Morning briefing: calendar, weather, finances, On This Day, media, infra."; };
      cron   = mkOption { type = types.str; default = "0 8 * * *"; };
    };

    nixUpdateSummary = {
      enable = mkOption { type = types.bool; default = true;
        description = "Weekly nix flake input staleness report."; };
      cron   = mkOption { type = types.str; default = "0 9 * * 1"; };
    };

    nightlyAnomalyScan = {
      enable   = mkOption { type = types.bool; default = true;
        description = "Nightly silent scan — posts to Matrix only on anomalies."; };
      cron     = mkOption { type = types.str; default = "0 2 * * *"; };
      services = mkOption { type = types.listOf types.str; default = []; };
      pools    = mkOption { type = types.listOf types.str; default = []; };
    };

    weeklyReview = {
      enable = mkOption { type = types.bool; default = true;
        description = "Friday weekly review ritual posted to Matrix."; };
      cron   = mkOption { type = types.str; default = "0 16 * * 5"; };
    };

    monthlyVaultMaintenance = {
      enable = mkOption { type = types.bool; default = true;
        description = "Monthly vault dedup, stale skill flagging, push to remote."; };
      cron   = mkOption { type = types.str; default = "0 10 1 * *"; };
    };

    weeklyStorageReport = {
      enable = mkOption { type = types.bool; default = true;
        description = "Weekly storage report: df + ZFS dataset sizes."; };
      cron   = mkOption { type = types.str; default = "0 9 * * 6"; };
    };

    vaultwardenAudit = {
      enable = mkOption { type = types.bool; default = false;
        description = "Monthly Vaultwarden password hygiene report."; };
      cron   = mkOption { type = types.str; default = "0 10 1 * *"; };
      apiUrl = mkOption { type = types.str; default = "http://localhost:8222"; };
    };

    # ── Life management integrations ──────────────────────────────────────────

    actualBudget = {
      enable          = mkOption { type = types.bool; default = false;
        description = "Wire Actual Budget API into hermes environment and enable budget skills/tasks."; };
      apiUrl          = mkOption { type = types.str; default = "http://localhost:5007";
        description = "Actual HTTP API base URL."; };
      apiKeyEnvVar    = mkOption { type = types.str; default = "ACTUAL_HTTP_API_KEY";
        description = "Env var name for the Actual HTTP API key."; };
      weeklyReport    = mkOption { type = types.bool; default = true;
        description = "Weekly budget pulse check — warns only when a category is over/approaching."; };
      weeklyReportCron = mkOption { type = types.str; default = "0 9 * * 5";
        description = "Schedule for weekly budget pulse (default: Friday 9am)."; };
      monthlyReport   = mkOption { type = types.bool; default = true;
        description = "End-of-month full budget breakdown posted to Matrix."; };
      monthlyReportCron = mkOption { type = types.str; default = "0 8 28 * *";
        description = "Schedule for monthly report (default: 28th of month 8am)."; };
      alertThreshold  = mkOption { type = types.int; default = 200;
        description = "Flag any single transaction above this amount (dollars)."; };
    };

    immich = {
      enable       = mkOption { type = types.bool; default = false;
        description = "Wire Immich API into hermes and enable photo skills/tasks."; };
      apiUrl       = mkOption { type = types.str; default = "http://localhost:2283"; };
      apiKeyEnvVar = mkOption { type = types.str; default = "IMMICH_API_KEY"; };
    };

    immichOnThisDay = {
      enable = mkOption { type = types.bool; default = true;
        description = "Daily 'On This Day' photo memory from Immich. Requires immich.enable."; };
      cron   = mkOption { type = types.str; default = "30 7 * * *"; };
    };

    n8n = {
      enable       = mkOption { type = types.bool; default = false;
        description = "Wire n8n API into hermes environment."; };
      baseUrl      = mkOption { type = types.str; default = "http://localhost:5678"; };
      apiKeyEnvVar = mkOption { type = types.str; default = "N8N_API_KEY"; };
    };

    notionSync = {
      enable          = mkOption { type = types.bool; default = false;
        description = "Enable Notion task integration skills and weekly stale-task audit."; };
      weeklyTaskAudit = mkOption { type = types.bool; default = true;
        description = "Weekly Notion task audit — flags tasks open >30 days."; };
      auditCron       = mkOption { type = types.str; default = "0 10 * * 1";
        description = "Schedule for stale task audit (default: Monday 10am)."; };
    };

    relationshipCrm = {
      enable      = mkOption { type = types.bool; default = true;
        description = "Seed relationship CRM skill and enable weekly nudge."; };
      weeklyNudge = mkOption { type = types.bool; default = true;
        description = "Sunday nudge: flag people not contacted in >60 days and upcoming birthdays."; };
      nudgeCron   = mkOption { type = types.str; default = "0 10 * * 0"; };
    };

    focusMode = {
      enable          = mkOption { type = types.bool; default = true;
        description = "Seed focus mode skill (no scheduled task — triggered by conversation)."; };
      defaultDuration = mkOption { type = types.int; default = 90;
        description = "Default focus session length in minutes."; };
    };

    # ── Homelab MCP ───────────────────────────────────────────────────────────

    homelabMcp = {
      enable        = mkOption { type = types.bool; default = true;
        description = "Enable hermes-homelab-mcp service and register it as an MCP server."; };
      port          = mkOption { type = types.port; default = 7830; };
      allowRestarts = mkOption { type = types.bool; default = false;
        description = "Expose restart_service MCP tool (requires confirmed_by on each call)."; };
    };

    # ── Passthroughs ──────────────────────────────────────────────────────────

    mcpServers = mkOption {
      type = types.attrs; default = {};
      description = "Additional MCP servers merged into services.hermes-agent.mcpServers.";
    };

    extraPlugins = mkOption {
      type = types.listOf types.package; default = [];
      description = "Extra plugins passed to services.hermes-agent.extraPlugins.";
    };

    extraSettings = mkOption {
      type = types.attrs; default = {};
      description = "Arbitrary settings merged into services.hermes-agent.settings.";
    };

    extraSkills = mkOption {
      type = types.listOf (types.submodule {
        options = {
          category = mkOption { type = types.str; };
          name     = mkOption { type = types.str; };
          content  = mkOption { type = types.str; };
        };
      });
      default = [];
      description = "Additional vault skills to seed at activation. Each becomes HERMES_HOME/skills/<category>/<name>/SKILL.md.";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

    # ── Upstream service ──────────────────────────────────────────────────────

    services.hermes-agent = {
      enable            = true;
      addToSystemPackages = true;

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
        // optionalAttrs cfg.actualBudget.enable {
             ACTUAL_API_URL     = cfg.actualBudget.apiUrl;
             ACTUAL_API_KEY_ENV = cfg.actualBudget.apiKeyEnvVar;
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
    # load_soul_md() reads HERMES_HOME/SOUL.md, not workingDirectory.

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

    # ── Skill seeding ─────────────────────────────────────────────────────────

    system.activationScripts.hermesAgentSkills = mkIf (skillsToSeed != []) {
      text = ''
        HERMES_HOME=/var/lib/hermes-agent/.hermes \
          ${pkgs.python3}/bin/python3 ${skillSeedScript} \
          ${escapeShellArg (builtins.toJSON skillsToSeed)}
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };

    # ── Cron job seeding ──────────────────────────────────────────────────────

    system.activationScripts.hermesAgentCronJobs = mkIf (allScheduledTasks != []) {
      text = let
        cronSeedScript = pkgs.writeText "hermes-cron-seed.py" ''
          #!/usr/bin/env python3
          """Seed nix-declared cron jobs into HERMES_HOME/cron/jobs.json. Idempotent."""
          import json, os, sys, uuid
          from pathlib import Path
          from datetime import datetime, timezone

          CRON_DIR = Path(os.environ["HERMES_HOME"]) / "cron"
          JOBS_FILE = CRON_DIR / "jobs.json"
          CRON_DIR.mkdir(parents=True, exist_ok=True)

          declared = json.loads(sys.argv[1])

          try:
              jobs = json.loads(JOBS_FILE.read_text())
          except (FileNotFoundError, json.JSONDecodeError):
              jobs = []

          # Remove stale nix-managed entries, keep user-created ones
          jobs = [j for j in jobs if "nix-managed" not in j.get("tags", [])]

          now = datetime.now(timezone.utc).isoformat()
          for task in declared:
              stable_id = "nix-" + uuid.uuid5(uuid.NAMESPACE_DNS, task["name"]).hex[:12]
              jobs.append({
                  "id":          stable_id,
                  "name":        task["name"],
                  "prompt":      task["prompt"],
                  "schedule":    {"kind": "cron", "expr": task["cron"]},
                  "enabled":     True,
                  "state":       "scheduled",
                  "tags":        ["nix-managed"],
                  "created_at":  now,
                  "last_run_at": None,
                  "run_count":   0,
                  "next_run_at": None,
              })

          tmp = JOBS_FILE.with_suffix(".tmp")
          tmp.write_text(json.dumps(jobs, indent=2))
          tmp.replace(JOBS_FILE)
          managed = [j for j in jobs if "nix-managed" in j.get("tags", [])]
          print(f"hermes-cron-seed: {len(managed)} nix-managed jobs written")
        '';
      in ''
        HERMES_HOME=/var/lib/hermes-agent/.hermes \
          ${pkgs.python3}/bin/python3 ${cronSeedScript} \
          ${escapeShellArg (builtins.toJSON (map (t: {
            inherit (t) name cron prompt;
          }) allScheduledTasks))}
      '';
      deps = [ "hermes-agent-setup" "users" "groups" ];
    };

    # ── Homelab MCP wiring ────────────────────────────────────────────────────

    modules.services.ai.hermes-homelab-mcp = mkIf cfg.homelabMcp.enable {
      enable              = true;
      port                = cfg.homelabMcp.port;
      allowRestarts       = cfg.homelabMcp.allowRestarts;
      environmentFile     = cfg.environmentFile;
      immichApiKeyEnvVar  = cfg.immich.apiKeyEnvVar;
      actualApiKeyEnvVar  = cfg.actualBudget.apiKeyEnvVar;
    };
  };
}
