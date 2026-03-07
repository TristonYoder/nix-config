{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.auto-update;

  # Helper to run kdialog as the graphical session user
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

  # Script to check if a newer closure is available on the NFS share
  check-update = pkgs.writeShellScript "check-update" ''
    PATH_FILE="${cfg.nfsMountPoint}/${config.networking.hostName}.path"

    # Check if NFS mount is accessible and path file exists
    if [ ! -f "$PATH_FILE" ]; then
      exit 0
    fi

    AVAILABLE_PATH=$(cat "$PATH_FILE" 2>/dev/null)
    CURRENT_PATH=$(readlink -f /run/current-system)

    if [ -z "$AVAILABLE_PATH" ] || [ "$AVAILABLE_PATH" = "$CURRENT_PATH" ]; then
      exit 0
    fi

    # Find graphical session user via loginctl
    DISPLAY_USER=$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend | while read -r sid uid user seat rest; do
      TYPE=$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p Type --value 2>/dev/null)
      if [ "$TYPE" = "wayland" ] || [ "$TYPE" = "x11" ]; then
        echo "$user"
        break
      fi
    done)
    if [ -z "$DISPLAY_USER" ]; then
      exit 0
    fi

    # Check if we already notified for this version
    NOTIFIED_FILE="/tmp/auto-update-notified"
    if [ -f "$NOTIFIED_FILE" ] && [ "$(cat "$NOTIFIED_FILE")" = "$AVAILABLE_PATH" ]; then
      exit 0
    fi

    # Show dialog as the logged-in user
    ${run-dialog} "$DISPLAY_USER" \
      --title "System Update" \
      --yesno "A system update is available.\n\nApply now?" \
      && ACCEPTED=1 || ACCEPTED=0

    if [ "$ACCEPTED" = "1" ]; then
      ${run-dialog} "$DISPLAY_USER" \
        --title "System Update" \
        --passivepopup "Applying system update..." 5 &

      if ${apply-update} "$AVAILABLE_PATH"; then
        ${run-dialog} "$DISPLAY_USER" \
          --title "System Update" \
          --passivepopup "System update applied successfully." 10
      else
        ${run-dialog} "$DISPLAY_USER" \
          --title "System Update" \
          --error "System update failed.\nCheck: journalctl -u auto-update-check"
      fi
    else
      # User declined - don't ask again for this version
      echo "$AVAILABLE_PATH" > "$NOTIFIED_FILE"
    fi
  '';

  # Script to apply the update
  apply-update = pkgs.writeShellScript "apply-update" ''
    set -e
    STORE_PATH="$1"
    CACHE_PATH="${cfg.nfsMountPoint}/cache"

    echo "Copying closure from binary cache..."
    ${pkgs.nix}/bin/nix copy --from "file://$CACHE_PATH" --no-check-sigs "$STORE_PATH"

    echo "Setting system profile..."
    ${pkgs.nix}/bin/nix-env -p /nix/var/nix/profiles/system --set "$STORE_PATH"

    echo "Switching to new configuration..."
    "$STORE_PATH"/bin/switch-to-configuration switch

    echo "Update complete."
  '';
in
{
  options.modules.system.auto-update = {
    enable = mkEnableOption "Automatic update checking from NFS binary cache";

    buildHost = mkOption {
      type = types.str;
      default = "david.theyoder.family";
      description = "Hostname of the build server that provides closures via NFS";
    };

    nfsMountPoint = mkOption {
      type = types.str;
      default = "/mnt/nix-builds";
      description = "Local mount point for the NFS share containing built closures";
    };

    nfsDevice = mkOption {
      type = types.str;
      default = "david.theyoder.family:/data/nix-builds";
      description = "NFS device string for the builds share";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "30min";
      description = "How often to check for updates (systemd calendar format)";
    };
  };

  config = mkIf cfg.enable {
    # Mount the nix-builds NFS share (automount so it doesn't block boot)
    fileSystems.${cfg.nfsMountPoint} = {
      device = cfg.nfsDevice;
      fsType = "nfs";
      options = [
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
        "x-systemd.mount-timeout=10"
        "soft"
        "timeo=50"
        "retrans=3"
        "ro"
      ];
    };

    # Timer to periodically check for updates
    systemd.timers.auto-update-check = {
      description = "Check for system updates on NFS";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.checkInterval;
        RandomizedDelaySec = "5min";
      };
    };

    systemd.services.auto-update-check = {
      description = "Check for and apply system updates from NFS binary cache";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = check-update;
      };
      path = [ pkgs.nix pkgs.coreutils ];
    };

    environment.systemPackages = [ pkgs.nfs-utils ];
  };
}
