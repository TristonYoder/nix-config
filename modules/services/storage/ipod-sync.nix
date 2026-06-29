{ config, lib, pkgs, iopodcli, ... }:

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
    # Pull iopod (Qt-free headless CLI) from the iOpenPodCLI flake overlay
    nixpkgs.overlays = [ iopodcli.overlays.default ];

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

            # Find the FAT partition on the first Apple block device
            DEVICE=$(${pkgs.util-linux}/bin/lsblk -ndo NAME,VENDOR \
              | ${pkgs.gnugrep}/bin/grep -i "apple" \
              | ${pkgs.gawk}/bin/awk '{print "/dev/" $1}' \
              | head -1)

            if [ -z "$DEVICE" ]; then
              echo "No Apple USB storage device found — skipping sync."
              exit 0
            fi

            PART=$(${pkgs.util-linux}/bin/lsblk -nrpo NAME,TYPE "$DEVICE" \
              | ${pkgs.gnugrep}/bin/grep part \
              | ${pkgs.gawk}/bin/awk '{print $1}' \
              | head -1)
            PART="''${PART:-$DEVICE}"

            # Mount via udisks (under /run/media/<user>) if not already mounted
            MOUNT=$(${pkgs.util-linux}/bin/lsblk -nro NAME,MOUNTPOINTS \
              | ${pkgs.gnugrep}/bin/grep "$(basename $PART)" \
              | ${pkgs.gawk}/bin/awk '{print $2}')

            MOUNTED_HERE=0
            if [ -z "$MOUNT" ]; then
              echo "Mounting $PART via udisksctl..."
              UDISKS_OUT=$(${pkgs.udisks2}/bin/udisksctl mount -b "$PART" --no-user-interaction)
              MOUNT=$(echo "$UDISKS_OUT" | ${pkgs.gnugrep}/bin/grep -oP '(?<=at ).*' | tr -d '.')
              MOUNTED_HERE=1
            fi

            if [ -z "$MOUNT" ]; then
              echo "Failed to determine mount point — aborting."
              exit 1
            fi

            echo "iPod at $MOUNT"
            cleanup() {
              if [ "$MOUNTED_HERE" = "1" ]; then
                echo "Unmounting $PART"
                ${pkgs.udisks2}/bin/udisksctl unmount -b "$PART" --no-user-interaction || true
              fi
            }
            trap cleanup EXIT

            ${pkgs.iopod}/bin/iopod --device "$MOUNT" --config ${cfg.configFile}
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
