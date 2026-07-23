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

    autoMount = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Kept for backwards compatibility. The service always reuses an existing
        KDE/udisks mount and falls back to mounting directly if none is found.
      '';
    };

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/ipod";
      description = "Fallback mount point when the device is not already mounted";
    };

    cacheDir = mkOption {
      type = types.str;
      default = "/var/cache/iopod";
      description = "Directory for pre-staged fingerprints and podcast episodes";
    };

    prepareInterval = mkOption {
      type = types.str;
      default = "hourly";
      description = "How often to run iopod prepare (systemd calendar expression)";
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [ iopodcli.overlays.default ];

    systemd.tmpfiles.rules = [
      "d ${cfg.mountPoint} 0755 root root -"
      "d ${cfg.cacheDir} 0755 ${cfg.user} ${cfg.user} -"
    ];

    # ── prepare: runs on a timer, no iPod needed ─────────────────────────────
    # Fingerprints playlist tracks and downloads podcast episodes ahead of time
    # so ipod-sync.service is fast when the iPod connects.
    systemd.services.iopod-prepare = {
      description = "Pre-stage iPod sync content (fingerprint + podcast download)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        TimeoutStartSec = "2h";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "iopod-prepare";
        ExecStart = "${pkgs.iopod}/bin/iopod prepare --config ${cfg.configFile} --cache-dir ${cfg.cacheDir}";
      };
    };

    systemd.timers.iopod-prepare = {
      description = "Run iopod prepare on a schedule";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.prepareInterval;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    # ── sync: triggered by udev on iPod connect ───────────────────────────────
    systemd.services.ipod-sync = {
      description = "Sync iPod via iopod";
      after = [ "network.target" ];
      wants = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        TimeoutStartSec = "2h";
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "ipod-sync";
        ExecStart = pkgs.writeShellScript "ipod-sync-run" ''
            set -euo pipefail

            MOUNT="${cfg.mountPoint}"

            DEVICE=$(${pkgs.util-linux}/bin/lsblk -ndo NAME,VENDOR \
              | { ${pkgs.gnugrep}/bin/grep -i "apple" || true; } \
              | ${pkgs.gawk}/bin/awk '{print "/dev/" $1}' \
              | head -1)

            if [ -z "$DEVICE" ]; then
              echo "No Apple USB storage device found -- skipping sync."
              exit 0
            fi

            PART=$(${pkgs.util-linux}/bin/lsblk -nrpo NAME,TYPE "$DEVICE" \
              | ${pkgs.gnugrep}/bin/grep part \
              | ${pkgs.gawk}/bin/awk '{print $1}' \
              | head -1)
            PART="''${PART:-$DEVICE}"

            EXISTING=$(${pkgs.util-linux}/bin/lsblk -nro NAME,MOUNTPOINTS \
              | ${pkgs.gnugrep}/bin/grep "$(basename "$PART")" \
              | ${pkgs.gawk}/bin/awk '{print $2}' | head -1)

            MOUNTED_HERE=0
            if [ -n "$EXISTING" ]; then
              MOUNT="$EXISTING"
              echo "iPod already mounted at $MOUNT"
            else
              mkdir -p "$MOUNT"
              echo "Mounting $PART -> $MOUNT"
              ${pkgs.util-linux}/bin/mount -t vfat \
                -o uid=$(id -u ${cfg.user}),gid=$(id -g ${cfg.user}),umask=002,flush \
                "$PART" "$MOUNT"
              MOUNTED_HERE=1
            fi

            cleanup() {
              if [ "$MOUNTED_HERE" = "1" ]; then
                echo "Unmounting $MOUNT"
                ${pkgs.util-linux}/bin/umount "$MOUNT" || true
              fi
            }
            trap cleanup EXIT

            ${pkgs.util-linux}/bin/runuser -u ${cfg.user} -- \
              ${pkgs.iopod}/bin/iopod sync \
                --device "$MOUNT" \
                --config ${cfg.configFile} \
                --cache-dir ${cfg.cacheDir}
          '';
      };
    };

    # Triggered on the block/disk uevent (not the raw USB device uevent) so that
    # /dev/sdX already exists by the time the service runs. Triggering on the USB
    # device add event instead races the kernel's SCSI probe: the service can start
    # and run lsblk before the block device is enumerated, finding nothing.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{ID_VENDOR_ID}=="05ac", ENV{ID_MODEL_ID}=="12[0-9a-f][0-9a-f]", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ipod-sync.service"
    '';
  };
}
