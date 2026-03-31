{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.storage.mp3PlayerSync;
  mountPoint = "/mnt/mp3-player";
  playlistNamesFile = pkgs.writeText "mp3-sync-playlist-names" (concatStringsSep "\n" cfg.playlists + "\n");
in
{
  options.modules.services.storage.mp3PlayerSync = {
    enable = mkEnableOption "USB MP3 player Jellyfin playlist sync";

    uuid = mkOption {
      type = types.str;
      description = "FAT32 partition UUID of the MP3 player";
    };

    musicLibrary = mkOption {
      type = types.str;
      default = "/data/media/Music";
      description = "Root of the local music library (used to derive relative paths for rsync)";
    };

    jellyfinUrl = mkOption {
      type = types.str;
      default = "http://localhost:8096";
      description = "Base URL of the Jellyfin server";
    };

    jellyfinApiKeyFile = mkOption {
      type = types.str;
      description = "Path to file containing the Jellyfin API key";
    };

    playlists = mkOption {
      type = types.listOf types.str;
      description = "Jellyfin playlist names to sync to the player";
      example = [ "Judah Jams 2" ];
    };
  };

  config = mkIf cfg.enable {
    # Ensure mount point exists
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 root root -"
    ];

    # Oneshot service: mount -> resolve playlists via Jellyfin API -> sync -> delete removed tracks -> unmount
    systemd.services.mp3-player-sync = {
      description = "Sync Jellyfin playlists to USB MP3 player";
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "infinity";
        ExecStart = pkgs.writeShellScript "mp3-player-sync" ''
          set -euo pipefail
          DEVICE="/dev/disk/by-uuid/${cfg.uuid}"
          MOUNT="${mountPoint}"
          MUSIC="${cfg.musicLibrary}"
          JELLYFIN="${cfg.jellyfinUrl}"
          API_KEY=$(cat "${cfg.jellyfinApiKeyFile}")
          WANTED_LIST="/tmp/mp3-sync-files.txt"

          echo "Mounting $DEVICE -> $MOUNT..."
          ${pkgs.util-linux}/bin/mount -t vfat -o uid=1000,gid=1000,umask=002,flush "$DEVICE" "$MOUNT"

          cleanup() {
            echo "Unmounting $MOUNT..."
            ${pkgs.util-linux}/bin/umount "$MOUNT" || true
            rm -f "$WANTED_LIST"
          }
          trap cleanup EXIT

          # Resolve each playlist name to file paths via the Jellyfin API.
          # The Path field is admin-only, so this requires an admin API key.
          echo "Resolving playlists from Jellyfin..."
          : > "$WANTED_LIST"

          # Get admin user ID (required by the playlist items endpoint)
          USER_ID=$(${pkgs.curl}/bin/curl -sf \
            -H "X-Emby-Token: $API_KEY" \
            "$JELLYFIN/Users?isAdministrator=true" \
            | ${pkgs.jq}/bin/jq -r '.[0].Id')

          if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
            echo "Error: could not retrieve admin user ID from Jellyfin" >&2
            exit 1
          fi
          echo "Using admin user ID: $USER_ID"

          while IFS= read -r PLAYLIST_NAME; do
            [ -z "$PLAYLIST_NAME" ] && continue
            echo "  Looking up: $PLAYLIST_NAME"

            # Find playlist ID by name
            PLAYLIST_ID=$(${pkgs.curl}/bin/curl -sf \
              -H "X-Emby-Token: $API_KEY" \
              "$JELLYFIN/Items?IncludeItemTypes=Playlist&Recursive=true&SearchTerm=$(${pkgs.python3}/bin/python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$PLAYLIST_NAME")" \
              | ${pkgs.jq}/bin/jq -r --arg name "$PLAYLIST_NAME" \
                  '.Items[] | select(.Name == $name) | .Id' \
              | head -1)

            if [ -z "$PLAYLIST_ID" ]; then
              echo "  Warning: playlist not found in Jellyfin: $PLAYLIST_NAME" >&2
              continue
            fi

            echo "  Found playlist ID: $PLAYLIST_ID"

            # Get all items in the playlist and extract their file paths
            ${pkgs.curl}/bin/curl -sf \
              -H "X-Emby-Token: $API_KEY" \
              "$JELLYFIN/Playlists/$PLAYLIST_ID/Items?userId=$USER_ID&Fields=Path&Limit=10000" \
              | ${pkgs.jq}/bin/jq -r '.Items[].Path' \
              | ${pkgs.gnused}/bin/sed "s|^$MUSIC/||" \
              >> "$WANTED_LIST"

          done < "${playlistNamesFile}"

          # Deduplicate
          sort -u -o "$WANTED_LIST" "$WANTED_LIST"

          COUNT=$(wc -l < "$WANTED_LIST")
          echo "Found $COUNT unique tracks across playlists."

          if [ "$COUNT" -eq 0 ]; then
            echo "No tracks found — aborting to avoid wiping device."
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
