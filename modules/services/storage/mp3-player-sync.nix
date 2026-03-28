{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.mp3PlayerSync;
  mountPoint = "/mnt/mp3-player";
in
{
  options.modules.services.storage.mp3PlayerSync = {
    enable = mkEnableOption "USB MP3 player playlist sync";

    uuid = mkOption {
      type = types.str;
      description = "FAT32 partition UUID of the MP3 player";
    };

    musicLibrary = mkOption {
      type = types.str;
      default = "/data/media/Music";
      description = "Root of the local music library";
    };

    playlistDir = mkOption {
      type = types.str;
      description = "Directory containing playlist files to sync";
    };

    playlistPattern = mkOption {
      type = types.str;
      default = "*.m3u";
      description = "Glob pattern for playlist files within playlistDir";
    };
  };

  config = mkIf cfg.enable {
    # Ensure mount point exists
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 root root -"
    ];

    # Oneshot service: mount -> build file list from playlists -> sync -> delete removed tracks -> unmount
    systemd.services.mp3-player-sync = {
      description = "Sync playlists to USB MP3 player";
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "mp3-player-sync" ''
          set -euo pipefail
          DEVICE="/dev/disk/by-uuid/${cfg.uuid}"
          MOUNT="${mountPoint}"
          MUSIC="${cfg.musicLibrary}"
          PLAYLIST_DIR="${cfg.playlistDir}"
          WANTED_LIST="/tmp/mp3-sync-files.txt"

          echo "Mounting $DEVICE -> $MOUNT..."
          ${pkgs.util-linux}/bin/mount -t vfat -o uid=1000,gid=1000,umask=002,flush "$DEVICE" "$MOUNT"

          cleanup() {
            echo "Unmounting $MOUNT..."
            ${pkgs.util-linux}/bin/umount "$MOUNT" || true
            rm -f "$WANTED_LIST"
          }
          trap cleanup EXIT

          # Build list of wanted files from all matching playlists
          # M3U entries may be absolute paths — strip the music library prefix to get relative paths
          echo "Building file list from playlists in $PLAYLIST_DIR..."
          ${pkgs.findutils}/bin/find "$PLAYLIST_DIR" -name "${cfg.playlistPattern}" -type f \
            -exec grep -h -v '^#' {} + \
            | grep -v '^$' \
            | ${pkgs.gnused}/bin/sed "s|^$MUSIC/||" \
            | sort -u \
            > "$WANTED_LIST"

          COUNT=$(wc -l < "$WANTED_LIST")
          echo "Found $COUNT unique tracks across playlists."

          if [ "$COUNT" -eq 0 ]; then
            echo "No tracks found in playlists — aborting to avoid wiping device."
            exit 1
          fi

          # Copy wanted files to device, preserving Artist/Album/track structure
          echo "Syncing tracks to device..."
          ${pkgs.rsync}/bin/rsync -av \
            --files-from="$WANTED_LIST" \
            --no-perms --no-owner --no-group \
            "$MUSIC/" "$MOUNT/" || { rc=$?; [ $rc -eq 23 ] || exit $rc; }

          # Delete files on device that are no longer in any playlist
          echo "Removing tracks no longer in any playlist..."
          ${pkgs.findutils}/bin/find "$MOUNT" -type f \
            \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.ogg" -o -iname "*.aac" -o -iname "*.m4a" \) \
            | while IFS= read -r f; do
                rel="''${f#$MOUNT/}"
                if ! grep -qxF "$rel" "$WANTED_LIST"; then
                  echo "Removing: $rel"
                  rm "$f"
                fi
              done

          # Prune empty directories left behind by removals
          ${pkgs.findutils}/bin/find "$MOUNT" -type d -empty -delete 2>/dev/null || true

          echo "Sync complete."
        '';
      };
    };

    # Trigger the sync service when the player is plugged in
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${cfg.uuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="mp3-player-sync.service"
    '';
  };
}
