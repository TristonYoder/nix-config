{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.auto-update;

  # Run a GUI command in the context of the logged-in graphical user.
  run-as-user = pkgs.writeShellScript "run-as-user" ''
    USER="$1"
    shift
    USER_ID=$(id -u "$USER" 2>/dev/null) || exit 1
    RUNTIME_DIR="/run/user/$USER_ID"

    # Qt needs a display to connect to; without one kdialog aborts, which
    # used to read as "No". Prefer the user's Wayland socket, fall back to X.
    WAYLAND=$(cd "$RUNTIME_DIR" 2>/dev/null && ls wayland-[0-9]* 2>/dev/null | grep -v '\.lock$' | head -1)

    ${pkgs.util-linux}/bin/runuser -u "$USER" -- \
      env DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
          XDG_RUNTIME_DIR="$RUNTIME_DIR" \
          ''${WAYLAND:+WAYLAND_DISPLAY="$WAYLAND"} \
          DISPLAY=:0 \
      "$@" 2>/dev/null
  '';

  # Notifications and errors (kdialog); the update prompt itself uses zenity.
  run-dialog = pkgs.writeShellScript "run-dialog" ''
    USER="$1"
    shift
    exec ${run-as-user} "$USER" ${pkgs.kdePackages.kdialog}/bin/kdialog "$@"
  '';

  # Apply the update by switching to the latest GitHub flake build.
  # Runs as root (system service), so no sudo needed.
  apply-update = pkgs.writeShellScript "apply-update" ''
    set -e
    HOST="$(${pkgs.hostname}/bin/hostname)"
    echo "Rebuilding $HOST from github:${cfg.repoOwner}/${cfg.repoName}#$HOST ..."
    /run/current-system/sw/bin/nixos-rebuild switch \
      --flake "github:${cfg.repoOwner}/${cfg.repoName}#$HOST" \
      --refresh
  '';

  # Check GitHub Actions for the latest successful deploy run.
  # Compares its SHA to the running system's configurationRevision and
  # prompts the user (via kdialog) if an update is available.
  check-update = pkgs.writeShellScript "check-update" ''
    set -euo pipefail

    # Latest SHA from the last successful deploy run on GitHub
    RUN=$(${pkgs.curl}/bin/curl -sf --max-time 10 \
      "https://api.github.com/repos/${cfg.repoOwner}/${cfg.repoName}/actions/workflows/${cfg.workflowFile}/runs?status=success&branch=${cfg.branch}&per_page=1" \
      || true)
    LATEST_SHA=$(echo "$RUN" | ${pkgs.jq}/bin/jq -r '.workflow_runs[0].head_sha // empty' 2>/dev/null || true)
    BUILT_AT=$(echo "$RUN" | ${pkgs.jq}/bin/jq -r '.workflow_runs[0].updated_at // empty' 2>/dev/null || true)

    if [ -z "$LATEST_SHA" ]; then
      exit 0  # GitHub unreachable or no successful runs yet
    fi

    # SHA baked into the running system by system.configurationRevision.
    # Exposed only via nixos-version; there is no file under /run/current-system.
    CURRENT_SHA=$(/run/current-system/sw/bin/nixos-version --configuration-revision 2>/dev/null || echo "unknown")

    if [ "$LATEST_SHA" = "$CURRENT_SHA" ]; then
      exit 0  # Already up to date
    fi

    # "Skip this Build": never prompt for this SHA again; a newer build will.
    # (New file name on purpose: the old auto-update-deferred marker was also
    # written whenever kdialog crashed, so its contents can't be trusted.)
    SKIPPED_FILE="/var/cache/auto-update-skipped"
    if [ -f "$SKIPPED_FILE" ] && [ "$(cat "$SKIPPED_FILE")" = "$LATEST_SHA" ]; then
      exit 0
    fi

    # "Later": no prompts at all until the snooze expires.
    LATER_FILE="/var/cache/auto-update-later"
    NOW=$(date +%s)
    if [ -f "$LATER_FILE" ] && [ "$NOW" -lt "$(cat "$LATER_FILE" 2>/dev/null || echo 0)" ]; then
      exit 0
    fi

    # Find the logged-in graphical session user
    DISPLAY_USER=$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend \
      | while read -r sid uid user seat rest; do
          TYPE=$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p Type --value 2>/dev/null)
          if [ "$TYPE" = "wayland" ] || [ "$TYPE" = "x11" ]; then
            echo "$user"
            break
          fi
        done)

    if [ -z "$DISPLAY_USER" ]; then
      exit 0  # No graphical session — timer/login trigger will retry
    fi

    SHORT_SHA=$(echo "$LATEST_SHA" | cut -c1-7)

    # NixOS version of the new build, in nixos-version's format
    # (<release>.<nixpkgs date>.<nixpkgs rev>), from the nixpkgs input
    # locked at that commit. Falls back to the commit alone if GitHub is slow.
    RELEASE=""
    BUILD="$SHORT_SHA"
    LOCK=$(${pkgs.curl}/bin/curl -sf --max-time 10 \
      "https://raw.githubusercontent.com/${cfg.repoOwner}/${cfg.repoName}/$LATEST_SHA/flake.lock" || true)
    if [ -n "$LOCK" ]; then
      NODE=$(echo "$LOCK" | ${pkgs.jq}/bin/jq -r '.nodes.root.inputs.nixpkgs' || true)
      REV=$(echo "$LOCK" | ${pkgs.jq}/bin/jq -r --arg n "$NODE" '.nodes[$n].locked.rev // empty' || true)
      MODIFIED=$(echo "$LOCK" | ${pkgs.jq}/bin/jq -r --arg n "$NODE" '.nodes[$n].locked.lastModified // empty' || true)
      RELEASE=$(${pkgs.curl}/bin/curl -sf --max-time 10 \
        "https://raw.githubusercontent.com/NixOS/nixpkgs/$REV/lib/.version" || true)
      if [ -n "$REV" ] && [ -n "$MODIFIED" ] && [ -n "$RELEASE" ]; then
        BUILD="$RELEASE.$(date -u -d "@$MODIFIED" +%Y%m%d).$(echo "$REV" | cut -c1-7) ($SHORT_SHA)"
      else
        RELEASE=""
      fi
    fi

    BUILT_DATE=$(date -d "$BUILT_AT" '+%B %-d, %Y' 2>/dev/null || echo "unknown")
    DETAILS="''${RELEASE:+NixOS $RELEASE\n}Build: $BUILD\nUpdate: $BUILT_DATE"

    # --switch: only our buttons, in this order. zenity prints the label of
    # the button pressed; closing the window prints nothing.
    SHOWN_AT=$(date +%s)
    CHOICE=$(${run-as-user} "$DISPLAY_USER" ${pkgs.zenity}/bin/zenity \
      --question --switch --width=560 \
      --title "System Update Available" \
      --text "A new system build is ready.\n\n$DETAILS\n\nThis will download the latest system build from ${cfg.cacheHost}.\n\nThe current OS version will still be available from the boot menu." \
      --extra-button "Skip this Build" \
      --extra-button "Later" \
      --extra-button "Update Now" || true)

    case "$CHOICE" in
      "Update Now") ;;
      "Skip this Build") echo "$LATEST_SHA" > "$SKIPPED_FILE"; exit 0 ;;
      *)
        # Nothing chosen within 2s means the dialog never showed (no
        # display, crash): try again next run instead of snoozing.
        if [ -z "$CHOICE" ] && [ $(( $(date +%s) - SHOWN_AT )) -lt 2 ]; then
          echo "update prompt failed to show; will retry $SHORT_SHA" >&2
          exit 0
        fi
        # Later, or the window was closed
        echo $((NOW + ${toString cfg.laterSeconds})) > "$LATER_FILE"
        exit 0
        ;;
    esac

    rm -f "$LATER_FILE"
    {
      ${run-dialog} "$DISPLAY_USER" \
        --title "System Update" \
        --passivepopup "Applying update $SHORT_SHA — this may take a few minutes..." 10 &

      if ${apply-update}; then
        ${run-dialog} "$DISPLAY_USER" \
          --title "System Update" \
          --passivepopup "Update applied. Now running $SHORT_SHA." 10
      else
        ${run-dialog} "$DISPLAY_USER" \
          --title "System Update" \
          --error "Update failed.\nSee: journalctl -u auto-update-check"
      fi
    }
  '';
in
{
  options.modules.system.auto-update = {
    enable = mkEnableOption "Update notifier — prompts the graphical user when a new CI build is available";

    repoOwner = mkOption {
      type = types.str;
      default = "TristonYoder";
    };

    repoName = mkOption {
      type = types.str;
      default = "nix-config";
    };

    workflowFile = mkOption {
      type = types.str;
      default = "deploy-nixos-config.yml";
      description = "Workflow file whose last successful run defines the current deployed version";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
    };

    laterSeconds = mkOption {
      type = types.int;
      default = 86400;
      description = "How long \"Later\" silences the update prompt";
    };

    cacheHost = mkOption {
      type = types.str;
      default = "nix-cache.theyoder.family";
      description = "Binary cache named in the update prompt";
    };
  };

  config = mkIf cfg.enable {
    # State dir for the skip/later markers
    systemd.tmpfiles.rules = [
      "d /var/cache 755 root root -"
    ];

    systemd.services.auto-update-check = {
      description = "Check for NixOS updates via GitHub Actions API";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = check-update;
      };
      path = with pkgs; [ nix curl jq coreutils systemd util-linux ];
    };

    # Hourly recurring check
    systemd.timers.auto-update-check = {
      description = "Hourly NixOS update check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";   # also fires shortly after boot / autologin
        OnCalendar = "hourly";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };

    # On-login trigger: fires when the main user's D-Bus session socket appears,
    # which happens when their graphical session starts.
    systemd.paths.auto-update-on-login = {
      description = "Trigger update check on user graphical login";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        PathExists = "/run/user/${toString config.modules.system.users.mainUser.uid}/bus";
      };
      unitConfig.Unit = "auto-update-check.service";
    };
  };
}
