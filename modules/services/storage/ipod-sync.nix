{ config, lib, pkgs, iopenpod-flake, ... }:

with lib;
let
  cfg = config.modules.services.storage.ipodSync;
in
{
  options.modules.services.storage.ipodSync = {
    enable = mkEnableOption "iPod auto-sync via iopod";

    user = mkOption {
      type = types.str;
      description = "User to run the sync as (needs read access to music library)";
    };

    configFile = mkOption {
      type = types.str;
      description = "Path to the iopod YAML config file";
      example = "/home/tristonyoder/.config/iopenpodcli/config.yaml";
    };

    # On headless hosts (david) the iPod won't be auto-mounted by udisks.
    # Set this to have the service mount and unmount it manually.
    autoMount = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Mount the iPod manually before sync and unmount after.
        Use on headless/server hosts without a desktop session.
        On desktop hosts (KDE), leave false — udisks auto-mounts the device.
      '';
    };

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/ipod";
      description = "Mount point used when autoMount = true";
    };
  };

  config = mkIf cfg.enable {
    # Pull iopod from the iopenpod-flake overlay (Qt-free headless build)
    nixpkgs.overlays = [ iopenpod-flake.overlays.default ];

    systemd.tmpfiles.rules = mkIf cfg.autoMount [
      "d ${cfg.mountPoint} 0755 root root -"
    ];

    systemd.services.ipod-sync = {
      description = "Sync iPod via iopod";
      # Don't block boot if triggered at startup; only run on-demand from udev
      after = [ "network.target" ];
      wants = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        TimeoutStartSec = "5min";
        # Keep logs for the last 10 runs
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "ipod-sync";
        ExecStart = pkgs.writeShellScript "ipod-sync-run" (
          if cfg.autoMount then ''
            set -euo pipefail

            MOUNT="${cfg.mountPoint}"

            # Find the Apple USB mass storage device (first one found)
            DEVICE=$(${pkgs.util-linux}/bin/lsblk -ndo NAME,VENDOR \
              | ${pkgs.gnugrep}/bin/grep -i "apple" \
              | ${pkgs.gawk}/bin/awk '{print "/dev/" $1}' \
              | head -1)

            if [ -z "$DEVICE" ]; then
              echo "No Apple USB storage device found — skipping sync."
              exit 0
            fi

            # Find the FAT partition on the device
            PART=$(${pkgs.util-linux}/bin/lsblk -nrpo NAME,TYPE "$DEVICE" \
              | ${pkgs.gnugrep}/bin/grep part \
              | ${pkgs.gawk}/bin/awk '{print $1}' \
              | head -1)
            PART="''${PART:-$DEVICE}"

            echo "Mounting $PART -> $MOUNT"
            ${pkgs.util-linux}/bin/mount -t vfat -o uid=$(id -u ${cfg.user}),gid=$(id -g ${cfg.user}),umask=002,flush "$PART" "$MOUNT"

            cleanup() {
              echo "Unmounting $MOUNT"
              ${pkgs.util-linux}/bin/umount "$MOUNT" || true
            }
            trap cleanup EXIT

            ${pkgs.iopod}/bin/iopod --device "$MOUNT" --config ${cfg.configFile}
          '' else ''
            set -euo pipefail
            # On desktop hosts udisks auto-mounts the iPod; iopod
            # discovers it by scanning mounted volumes via scan_for_ipods().
            ${pkgs.iopod}/bin/iopod --config ${cfg.configFile}
          ''
        );
      };
    };

    # Trigger the sync when any Apple USB mass storage device is connected.
    # Apple Vendor ID: 05ac; iPod product IDs span 0x1200–0x12ff.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="12[0-9a-f][0-9a-f]", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ipod-sync.service"
    '';
  };
}
