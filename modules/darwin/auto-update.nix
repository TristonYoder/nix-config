{ config, lib, pkgs, ... }:

# macOS counterpart of modules/system/auto-update.nix: a root launchd daemon
# checks hourly for a newer CI-approved commit and, when there is one, shows
# a native dialog in the logged-in user's session. The dialog stays up until
# answered, like the zenity prompt on the NixOS laptops.

with lib;
let
  cfg = config.modules.system.auto-update;

  jq = "${pkgs.jq}/bin/jq";
  curl = "/usr/bin/curl";  # system curl: uses the macOS trust store
  gdate = "${pkgs.coreutils}/bin/date";

  # Modal dialog, run as the console user. Args: title, text, buttons...
  # Prints the button pressed. The last button is the default.
  # The icon is rendered from System Settings at runtime: macOS no longer
  # ships the Software Update icon (or most app icons) as a loose .icns.
  dialog = pkgs.writeText "auto-update-dialog.js" ''
    ObjC.import('AppKit');
    function run(argv) {
      var app = Application.currentApplication();
      app.includeStandardAdditions = true;
      var opts = {
        withTitle: argv[0],
        buttons: argv.slice(2),
        defaultButton: argv[argv.length - 1],
        withIcon: 'note'
      };
      try {
        var png = $.NSTemporaryDirectory().js + 'nix-auto-update-icon.png';
        var img = $.NSWorkspace.sharedWorkspace.iconForFile('/System/Applications/System Settings.app');
        img.size = { width: 256, height: 256 };
        var rep = $.NSBitmapImageRep.imageRepWithData(img.TIFFRepresentation);
        if (rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(png, true)) {
          opts.withIcon = Path(png);
        }
      } catch (e) {}
      app.activate();
      return app.displayDialog(argv[1], opts).buttonReturned;
    }
  '';

  apply-update = pkgs.writeShellScript "apply-update" ''
    set -e
    echo "Rebuilding ${cfg.flakeHost} from github:${cfg.repoOwner}/${cfg.repoName}#${cfg.flakeHost} ..."
    /run/current-system/sw/bin/darwin-rebuild switch \
      --flake "github:${cfg.repoOwner}/${cfg.repoName}#${cfg.flakeHost}" \
      --refresh
  '';

  # Installed into the system profile and launched by its stable path, so the
  # daemon's plist never changes. darwin-rebuild reloads daemons whose plist
  # changed, which would kill this script (and the rebuild it started)
  # mid-switch.
  check-update = pkgs.writeShellScriptBin "darwin-update-check" ''
    set -euo pipefail

    if [ "$(id -u)" != 0 ]; then
      echo "run as root: sudo darwin-update-check" >&2
      exit 1
    fi

    STATE=/var/db/nix-auto-update
    mkdir -p "$STATE"

    RUN=$(${curl} -sf --max-time 10 \
      "https://api.github.com/repos/${cfg.repoOwner}/${cfg.repoName}/actions/workflows/${cfg.workflowFile}/runs?status=success&branch=${cfg.branch}&per_page=1" \
      || true)
    LATEST_SHA=$(echo "$RUN" | ${jq} -r '.workflow_runs[0].head_sha // empty' 2>/dev/null || true)
    BUILT_AT=$(echo "$RUN" | ${jq} -r '.workflow_runs[0].updated_at // empty' 2>/dev/null || true)

    if [ -z "$LATEST_SHA" ]; then
      exit 0  # GitHub unreachable or no successful runs yet
    fi

    # Set by system.configurationRevision in common/darwin.nix
    CURRENT_SHA=$(/run/current-system/sw/bin/darwin-version --configuration-revision 2>/dev/null || echo unknown)
    if [ "$LATEST_SHA" = "$CURRENT_SHA" ]; then
      exit 0
    fi

    # "Skip this Build": never prompt for this SHA again; a newer build will.
    SKIPPED_FILE="$STATE/skipped"
    if [ -f "$SKIPPED_FILE" ] && [ "$(cat "$SKIPPED_FILE")" = "$LATEST_SHA" ]; then
      exit 0
    fi

    # "Later": no prompts until the snooze expires.
    LATER_FILE="$STATE/later"
    NOW=$(date +%s)
    if [ -f "$LATER_FILE" ] && [ "$NOW" -lt "$(cat "$LATER_FILE" 2>/dev/null || echo 0)" ]; then
      exit 0
    fi

    # Console user, i.e. whoever owns the GUI session. root/loginwindow means
    # nobody is logged in; the next hourly run will retry.
    CONSOLE_USER=$(/usr/bin/stat -f %Su /dev/console)
    case "$CONSOLE_USER" in
      root|loginwindow|"") exit 0 ;;
    esac
    CONSOLE_UID=$(id -u "$CONSOLE_USER")

    as_user() {
      /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" "$@"
    }
    show_dialog() {
      as_user /usr/bin/osascript -l JavaScript ${dialog} "$@" 2>/dev/null
    }

    SHORT_SHA=$(echo "$LATEST_SHA" | cut -c1-7)

    # nixpkgs version of the new build (<release>.<date>.<rev>), from the
    # nixpkgs input locked at that commit. Falls back to the commit alone.
    RELEASE=""
    BUILD="$SHORT_SHA"
    LOCK=$(${curl} -sf --max-time 10 \
      "https://raw.githubusercontent.com/${cfg.repoOwner}/${cfg.repoName}/$LATEST_SHA/flake.lock" || true)
    if [ -n "$LOCK" ]; then
      NODE=$(echo "$LOCK" | ${jq} -r '.nodes.root.inputs["${cfg.nixpkgsInput}"]' || true)
      REV=$(echo "$LOCK" | ${jq} -r --arg n "$NODE" '.nodes[$n].locked.rev // empty' || true)
      MODIFIED=$(echo "$LOCK" | ${jq} -r --arg n "$NODE" '.nodes[$n].locked.lastModified // empty' || true)
      if [ -n "$REV" ]; then
        RELEASE=$(${curl} -sf --max-time 10 \
          "https://raw.githubusercontent.com/NixOS/nixpkgs/$REV/lib/.version" || true)
      fi
      if [ -n "$REV" ] && [ -n "$MODIFIED" ] && [ -n "$RELEASE" ]; then
        BUILD="$RELEASE.$(${gdate} -u -d "@$MODIFIED" +%Y%m%d).$(echo "$REV" | cut -c1-7) ($SHORT_SHA)"
      else
        RELEASE=""
      fi
    fi

    BUILT_DATE=$(${gdate} -d "$BUILT_AT" '+%B %-d, %Y' 2>/dev/null || echo unknown)
    DETAILS="''${RELEASE:+nix-darwin $RELEASE
    }Build: $BUILD
    Update: $BUILT_DATE"

    SHOWN_AT=$(date +%s)
    CHOICE=$(show_dialog "System Update Available" "A new system build is ready.

    $DETAILS

    This will download the latest system build from ${cfg.cacheHost}.

    The current OS version can be restored by running rollback in a terminal." \
      "Skip this Build" "Later" "Update Now" || true)

    case "$CHOICE" in
      "Update Now") ;;
      "Skip this Build") echo "$LATEST_SHA" > "$SKIPPED_FILE"; exit 0 ;;
      *)
        # Nothing chosen within 2s means the dialog never showed: retry next
        # run instead of snoozing.
        if [ -z "$CHOICE" ] && [ $(( $(date +%s) - SHOWN_AT )) -lt 2 ]; then
          echo "update prompt failed to show; will retry $SHORT_SHA" >&2
          exit 0
        fi
        echo $((NOW + ${toString cfg.laterSeconds})) > "$LATER_FILE"
        exit 0
        ;;
    esac

    rm -f "$LATER_FILE"

    LOG=/var/log/auto-update.log
    : > "$LOG"
    chmod 644 "$LOG"
    ${apply-update} > "$LOG" 2>&1 &
    APPLY_PID=$!

    # Non-blocking status dialog; Console.app follows the log live.
    (
      if [ "$(show_dialog "Updating System" "Updating to $SHORT_SHA. You can keep working; you'll be told when it finishes." \
            "Show Progress" "OK" || true)" = "Show Progress" ]; then
        as_user /usr/bin/open -a Console "$LOG" || true
      fi
    ) &
    VIEW_PID=$!

    wait "$APPLY_PID" && RC=0 || RC=$?

    # Close the status dialog if it is still up
    /usr/bin/pkill -P "$VIEW_PID" 2>/dev/null || true
    /usr/bin/pkill -u "$CONSOLE_UID" -f "auto-update-dialog.js Updating System" 2>/dev/null || true

    if [ "$RC" = 0 ]; then
      show_dialog "Update Complete" "Your system is up to date.

    $DETAILS" "OK" >/dev/null || true
    else
      TAIL=$(tail -n 8 "$LOG" | cut -c1-120)
      if [ "$(show_dialog "Update Failed" "The update to $SHORT_SHA did not complete. The previous system is still active.

    $TAIL

    Full log: $LOG" "Show Log" "OK" || true)" = "Show Log" ]; then
        as_user /usr/bin/open -a Console "$LOG" || true
      fi
      exit 1
    fi
  '';
in
{
  options.modules.system.auto-update = {
    enable = mkEnableOption "Update notifier — prompts the console user when a new CI build is available";

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
      description = "Workflow file whose last successful run defines the current approved commit";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
    };

    flakeHost = mkOption {
      type = types.str;
      default = config.networking.hostName;
      defaultText = literalExpression "config.networking.hostName";
      description = "darwinConfigurations attribute to rebuild";
    };

    nixpkgsInput = mkOption {
      type = types.str;
      default = "nixpkgs-unstable";
      description = "Flake input whose version is shown in the prompt";
    };

    cacheHost = mkOption {
      type = types.str;
      default = "nix-cache.theyoder.family";
      description = "Binary cache named in the update prompt";
    };

    laterSeconds = mkOption {
      type = types.int;
      default = 86400;
      description = "How long \"Later\" silences the update prompt";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ check-update ];

    launchd.daemons.auto-update-check.serviceConfig = {
      ProgramArguments = [ "/run/current-system/sw/bin/darwin-update-check" ];
      RunAtLoad = true;
      StartInterval = 3600;
      StandardOutPath = "/var/log/auto-update-check.log";
      StandardErrorPath = "/var/log/auto-update-check.log";
      EnvironmentVariables = {
        PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        HOME = "/var/root";
      };
    };
  };
}
