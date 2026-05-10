{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.musicDedup;
in
{
  options.modules.services.media.musicDedup = {
    enable = mkEnableOption "daily music library hard-link deduplication";

    musicDir = mkOption {
      type = types.str;
      default = "/data/media/Music";
      description = "Path to the music library to deduplicate";
    };

    calendar = mkOption {
      type = types.str;
      default = "03:17";
      description = "Systemd OnCalendar expression for when to run (default: 3:17 AM daily)";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.music-dedup = {
      description = "Music library hard-link deduplication";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "music-dedup" ''
          set -euo pipefail
          MUSIC="${cfg.musicDir}"

          echo "=== music-dedup: $(date) ==="

          # 1. Hard-link exact byte-for-byte duplicates across albums
          echo "Hard-linking exact duplicates..."
          linked=$(${pkgs.jdupes}/bin/jdupes --recurse --link-hard "$MUSIC" 2>&1 | tail -1)
          echo "  jdupes: $linked"

          # 2. Remove numbered temp duplicates (e.g. "Song.1.flac", "Song.2.lrc")
          #    where the unnumbered version of the same file also exists.
          echo "Removing numbered duplicate files (*.N.ext)..."
          num_removed=0
          while IFS= read -r f; do
            ext="''${f##*.}"
            without_num="''${f%.*.*}.''${ext}"
            if [ -f "$without_num" ]; then
              echo "  Removing: $f"
              rm "$f"
              num_removed=$((num_removed + 1))
            fi
          done < <(
            find "$MUSIC" -type f \
              | ${pkgs.perl}/bin/perl -ne 'print if /\.\d+\.(flac|lrc|m4a|mp3)$/i'
          )
          echo "  Removed $num_removed numbered duplicate(s)."

          # 3. Remove M4A files where a FLAC version of the same track exists
          echo "Removing M4A files superseded by FLAC..."
          removed=0
          while IFS= read -r base; do
            if [ -f "''${base}.flac" ] && [ -f "''${base}.m4a" ]; then
              echo "  Removing: ''${base}.m4a"
              rm "''${base}.m4a"
              removed=$((removed + 1))
            fi
          done < <(
            find "$MUSIC" -type f \( -name "*.flac" -o -name "*.m4a" \) \
              | sed 's/\.[^.]*$//' | sort | uniq -d
          )
          echo "  Removed $removed M4A file(s)."

          echo "=== music-dedup done ==="
        '';
      };
    };

    systemd.timers.music-dedup = {
      description = "Daily music library hard-link deduplication timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.calendar;
        Persistent = true;
        Unit = "music-dedup.service";
      };
    };
  };
}
