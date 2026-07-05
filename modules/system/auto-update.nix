{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.auto-update;

  # Run kdialog in the context of the logged-in graphical user.
  run-dialog = pkgs.writeShellScript "run-dialog" ''
    USER="$1"
    shift
    USER_ID=$(id -u "$USER" 2>/dev/null) || exit 1
    RUNTIME_DIR="/run/user/$USER_ID"

    ${pkgs.util-linux}/bin/runuser -u "$USER" -- \
      env DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus" \
          XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      ${pkgs.kdePackages.kdialog}/bin/kdialog "$@" 2>/dev/null
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
    LATEST_SHA=$(${pkgs.curl}/bin/curl -sf --max-time 10 \
      "https://api.github.com/repos/${cfg.repoOwner}/${cfg.repoName}/actions/workflows/${cfg.workflowFile}/runs?status=success&branch=${cfg.branch}&per_page=1" \
      | ${pkgs.jq}/bin/jq -r '.workflow_runs[0].head_sha // empty' \
      || true)

    if [ -z "$LATEST_SHA" ]; then
      exit 0  # GitHub unreachable or no successful runs yet
    fi

    # SHA baked into the running system by system.configurationRevision
    CURRENT_SHA=$(cat /run/current-system/configuration-revision 2>/dev/null || echo "unknown")

    if [ "$LATEST_SHA" = "$CURRENT_SHA" ]; then
      exit 0  # Already up to date
    fi

    # Don't re-prompt for a version the user already deferred
    DEFERRED_FILE="/var/cache/auto-update-deferred"
    if [ -f "$DEFERRED_FILE" ] && [ "$(cat "$DEFERRED_FILE")" = "$LATEST_SHA" ]; then
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

    ${run-dialog} "$DISPLAY_USER" \
      --title "System Update Available" \
      --yesno "A new system build is ready ($SHORT_SHA).\n\nApply now? This runs 'nixos-rebuild switch'." \
      && APPLY=1 || APPLY=0

    if [ "$APPLY" = "1" ]; then
      ${run-dialog} "$DISPLAY_USER" \
        --title "System Update" \
        --passivepopup "Applying update $SHORT_SHA — this may take a few minutes..." 10 &

      if ${apply-update}; then
        rm -f "$DEFERRED_FILE"
        ${run-dialog} "$DISPLAY_USER" \
          --title "System Update" \
          --passivepopup "Update applied. Now running $SHORT_SHA." 10
      else
        ${run-dialog} "$DISPLAY_USER" \
          --title "System Update" \
          --error "Update failed.\nSee: journalctl -u auto-update-check"
      fi
    else
      # Remember this SHA so we don't re-prompt until a newer build lands
      echo "$LATEST_SHA" > "$DEFERRED_FILE"
    fi
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
  };

  config = mkIf cfg.enable {
    # State dir for the deferred-version marker
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
