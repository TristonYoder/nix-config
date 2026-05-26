{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.musicAlacSync;
in
{
  options.modules.services.media.musicAlacSync = {
    enable = mkEnableOption "nightly Music to ALAC sync for Apple Music";

    musicDir = mkOption {
      type = types.str;
      default = "/data/media/Music";
      description = "Source music library path";
    };

    appleMusicDir = mkOption {
      type = types.str;
      default = "/data/media/AppleMusic";
      description = "Destination ALAC library path mirroring the source";
    };

    calendar = mkOption {
      type = types.str;
      default = "04:17";
      description = "Systemd OnCalendar expression for when to run";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.music-alac-sync = {
      description = "Sync Music library to ALAC for Apple Music";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "music-alac-sync" ''
          set -euo pipefail
          MUSIC="${cfg.musicDir}"
          APPLE_MUSIC="${cfg.appleMusicDir}"
          FFMPEG="${pkgs.ffmpeg}/bin/ffmpeg"

          echo "=== music-alac-sync: $(date) ==="

          # Returns 0 if the extension is a supported audio format
          is_audio() {
            case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
              flac|mp3|m4a|wav|aiff|aif|ogg|opus|wma) return 0 ;;
              *) return 1 ;;
            esac
          }

          # 1. Forward sync: for each file in Music, ensure AppleMusic is up to date.
          #    Audio files are converted to ALAC .m4a; all other files are copied as-is.
          #    Files whose destination already exists are skipped (no re-encoding).
          echo "Forward sync: converting new audio files to ALAC..."
          converted=0
          copied=0
          while IFS= read -r src; do
            rel="''${src#$MUSIC/}"
            dest_dir="$APPLE_MUSIC/$(dirname "$rel")"
            base="$(basename "$rel")"
            stem="''${base%.*}"
            ext="''${base##*.}"

            if is_audio "$ext"; then
              dest="$dest_dir/$stem.m4a"
            else
              dest="$dest_dir/$base"
            fi

            [ -f "$dest" ] && continue

            mkdir -p "$dest_dir"
            if is_audio "$ext"; then
              echo "  Converting: $rel"
              $FFMPEG -i "$src" -c:a alac -c:v copy -map_metadata 0 "$dest" -y -loglevel error
              converted=$((converted + 1))
            else
              echo "  Copying: $rel"
              cp "$src" "$dest"
              copied=$((copied + 1))
            fi
          done < <(find "$MUSIC" -type f | sort)
          echo "  Converted $converted audio file(s), copied $copied other file(s)."

          # 2. Reverse sync: remove files from AppleMusic whose source no longer exists.
          #    For .m4a files, check for any audio source extension with the same stem.
          #    For all other files, check for the exact same relative path.
          echo "Reverse sync: removing orphaned files from AppleMusic..."
          removed=0
          while IFS= read -r dest; do
            rel="''${dest#$APPLE_MUSIC/}"
            dir="$(dirname "$rel")"
            base="$(basename "$rel")"
            stem="''${base%.*}"
            ext="''${base##*.}"

            found=0
            if [ "$ext" = "m4a" ]; then
              for src_ext in flac mp3 m4a wav aiff aif ogg opus wma; do
                if [ -f "$MUSIC/$dir/$stem.$src_ext" ]; then
                  found=1
                  break
                fi
              done
            else
              [ -f "$MUSIC/$rel" ] && found=1
            fi

            if [ "$found" = "0" ]; then
              echo "  Removing orphan: $rel"
              rm "$dest"
              removed=$((removed + 1))
            fi
          done < <(find "$APPLE_MUSIC" -type f | sort)

          # Clean up directories that became empty after removals
          find "$APPLE_MUSIC" -mindepth 1 -type d -empty -delete 2>/dev/null || true

          echo "  Removed $removed orphaned file(s)."
          echo "=== music-alac-sync done ==="
        '';
      };
    };

    systemd.timers.music-alac-sync = {
      description = "Nightly Music to ALAC sync timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.calendar;
        Persistent = true;
        Unit = "music-alac-sync.service";
      };
    };
  };
}
