{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.wiiHddSync;
  mountPoint = "/mnt/wii-hdd";
  # systemd escapes /mnt/wii-hdd as mnt-wii\x2dhdd
  mountUnit = "mnt-wii\\x2dhdd.mount";
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
    # Mount point directory
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 root root -"
    ];

    # noauto so it doesn't mount on boot — udev triggers it on plug-in
    fileSystems."${mountPoint}" = {
      device = "/dev/disk/by-uuid/${cfg.uuid}";
      fsType = "vfat";
      options = [ "noauto" "nofail" "uid=1000" "gid=1000" "umask=002" "flush" ];
    };

    # Trigger the mount unit when the drive is plugged in
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${cfg.uuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="${mountUnit}"
    '';

    # Sync service: runs once after mount, stopped when drive unplugged
    systemd.services.wii-hdd-sync = {
      description = "Sync Wii HDD wbfs <-> local storage";
      after = [ mountUnit ];
      bindsTo = [ mountUnit ];
      wantedBy = [ mountUnit ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "wii-hdd-sync" ''
          set -euo pipefail
          echo "Syncing drive -> local..."
          ${pkgs.rsync}/bin/rsync -av --ignore-existing \
            ${mountPoint}/wbfs/ ${cfg.localWbfs}/

          echo "Syncing local -> drive..."
          ${pkgs.rsync}/bin/rsync -av --ignore-existing \
            ${cfg.localWbfs}/ ${mountPoint}/wbfs/

          echo "Sync complete."
        '';
      };
    };
  };
}
