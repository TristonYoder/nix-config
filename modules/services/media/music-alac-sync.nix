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
          set -uo pipefail
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
          #    Run find from within $MUSIC so paths are always relative — no stripping needed.
          echo "Forward sync: converting new audio files to ALAC..."
          converted=0
          copied=0
          errors=0
          cd "$MUSIC"
          # fd 3 carries the find stream so ffmpeg/cp don't consume stdin and corrupt the path stream
          while IFS= read -r -d "" rel <&3; do
            rel="''${rel#./}"
            src="$MUSIC/$rel"
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

              # Check whether the source already has an embedded image stream
              src_has_cover=0
              if ${pkgs.ffmpeg}/bin/ffprobe -i "$src" -show_streams -select_streams v \
                  -loglevel error 2>/dev/null | grep -q "codec_type=video"; then
                src_has_cover=1
              fi

              # If no embedded art, look for a cover image file alongside the source
              cover_file=""
              if [ "$src_has_cover" = "0" ]; then
                for cover_name in cover.jpg cover.png folder.jpg folder.png; do
                  if [ -f "$(dirname "$src")/$cover_name" ]; then
                    cover_file="$(dirname "$src")/$cover_name"
                    break
                  fi
                done
              fi

              # -map 0         — include all streams from source (audio + embedded art)
              # -map_metadata 0 — copy all metadata tags (title, artist, album, year, genre, lyrics, ISRC…)
              # -map_chapters 0 — copy chapter markers (useful for audiobooks)
              # -c:a alac      — convert audio to Apple Lossless
              # -c:v copy      — copy embedded image stream without re-encoding
              if [ -n "$cover_file" ]; then
                # Source has no embedded art but a cover file exists — inject it
                if ! $FFMPEG -i "$src" -i "$cover_file" \
                    -map 0:a -map 1:v \
                    -map_metadata 0 -map_chapters 0 \
                    -c:a alac -c:v mjpeg \
                    -metadata:s:v:0 title="Album cover" \
                    -metadata:s:v:0 comment="Cover (front)" \
                    "$dest" -y -loglevel error 2>&1; then
                  echo "  ERROR: failed to convert $rel"
                  rm -f "$dest"
                  errors=$((errors + 1))
                else
                  converted=$((converted + 1))
                fi
              else
                if ! $FFMPEG -i "$src" \
                    -map 0 \
                    -map_metadata 0 -map_chapters 0 \
                    -c:a alac -c:v copy \
                    "$dest" -y -loglevel error 2>&1; then
                  echo "  ERROR: failed to convert $rel"
                  rm -f "$dest"
                  errors=$((errors + 1))
                else
                  converted=$((converted + 1))
                fi
              fi
            else
              echo "  Copying: $rel"
              cp "$src" "$dest"
              copied=$((copied + 1))
            fi
          done 3< <(find . -type f -print0)
          echo "  Converted $converted audio file(s), copied $copied other file(s), $errors error(s)."

          # 2. Reverse sync: remove files from AppleMusic whose source no longer exists.
          #    For .m4a files, check for any audio source extension with the same stem.
          #    For all other files, check for the exact same relative path.
          echo "Reverse sync: removing orphaned files from AppleMusic..."
          removed=0
          cd "$APPLE_MUSIC"
          while IFS= read -r -d "" rel <&3; do
            rel="''${rel#./}"
            dest="$APPLE_MUSIC/$rel"
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
          done 3< <(find . -type f -print0)

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
