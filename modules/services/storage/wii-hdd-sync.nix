{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.wiiHddSync;
  mountPoint = "/mnt/wii-hdd";
in
{
  options.modules.services.storage.wiiHddSync = {
    enable = mkEnableOption "Wii HDD bidirectional wbfs sync";

    uuid = mkOption {
      type = types.str;
      default = "16F4-2275";
      description = "FAT32 partition UUID of the Wii HDD";
    };

    localWbfs = mkOption {
      type = types.str;
      default = "/data/media/Games/Emulation/roms/wii/wbfs";
      description = "Local wbfs directory to sync with";
    };
  };

  config = mkIf cfg.enable {
    # Ensure mount point exists
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 root root -"
    ];

    # Oneshot service: mount -> sync both ways -> unmount
    systemd.services.wii-hdd-sync = {
      description = "Sync Wii HDD wbfs <-> local storage";
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "wii-hdd-sync" ''
          set -euo pipefail
          DEVICE="/dev/disk/by-uuid/${cfg.uuid}"
          MOUNT="${mountPoint}"
          LOCAL="${cfg.localWbfs}"

          echo "Mounting $DEVICE -> $MOUNT..."
          ${pkgs.util-linux}/bin/mount -t vfat -o uid=1000,gid=1000,umask=002,flush "$DEVICE" "$MOUNT"

          cleanup() {
            echo "Unmounting $MOUNT..."
            ${pkgs.util-linux}/bin/umount "$MOUNT" || true
          }
          trap cleanup EXIT

          echo "Syncing drive -> local..."
          ${pkgs.rsync}/bin/rsync -av --ignore-existing "$MOUNT/wbfs/" "$LOCAL/"

          echo "Syncing local -> drive..."
          ${pkgs.rsync}/bin/rsync -av --ignore-existing "$LOCAL/" "$MOUNT/wbfs/"

          echo "Sync complete."
        '';
      };
    };

    # Trigger the sync service when the drive is plugged in
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${cfg.uuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="wii-hdd-sync.service"
    '';
  };
}
