# Self-hosted single-subscriber podcast feed for the daily brief audio
# script. A `daily-brief-podcast publish` CLI synthesizes speech locally via
# Piper, encodes it to mp3, and regenerates an RSS 2.0 feed with an iTunes
# namespace so `iopod` (see ipod-sync.nix) can subscribe to it exactly like
# any other podcast. Caddy serves the episode directory as static files —
# internal-only, since the brief contains personal/ministry content.
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.dailyBriefPodcast;

  voiceModelRaw = pkgs.fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx";
    hash = "sha256-s5kNdgbhg+yNv7pwpGBwdPFi3hoMQS4BgNH/YLsVTso=";
  };
  voiceConfigRaw = pkgs.fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx.json";
    hash = "sha256-xtO5jwgxXLS+vw1J1Q/E/0kbUDxkuUDNPVyihUO0gBE=";
  };

  # piper's --config flag is parsed but never forwarded to PiperVoice.load()
  # (it always looks for "<model_path>.json"), so the config must sit next
  # to the model on disk under a matching name rather than being passed
  # explicitly on the command line.
  voiceDir = pkgs.runCommand "piper-voice-en_US-ryan-high" { } ''
    mkdir -p "$out"
    ln -s ${voiceModelRaw} "$out/en_US-ryan-high.onnx"
    ln -s ${voiceConfigRaw} "$out/en_US-ryan-high.onnx.json"
  '';
  voiceModel = "${voiceDir}/en_US-ryan-high.onnx";

  publishScript = pkgs.writeShellApplication {
    name = "daily-brief-podcast";
    runtimeInputs = [ pkgs.piper-tts pkgs.ffmpeg pkgs.coreutils pkgs.gnused pkgs.findutils ];
    text = ''
      usage() {
        echo "Usage: daily-brief-podcast publish --title TITLE --text-file PATH [--date YYYY-MM-DD]" >&2
        exit 1
      }

      [ "''${1:-}" = "publish" ] || usage
      shift

      TITLE=""
      TEXT_FILE=""
      EP_DATE="$(date +%F)"

      while [ $# -gt 0 ]; do
        case "$1" in
          --title) TITLE="$2"; shift 2 ;;
          --text-file) TEXT_FILE="$2"; shift 2 ;;
          --date) EP_DATE="$2"; shift 2 ;;
          *) usage ;;
        esac
      done

      [ -n "$TITLE" ] && [ -n "$TEXT_FILE" ] || usage
      [ -f "$TEXT_FILE" ] || { echo "text file not found: $TEXT_FILE" >&2; exit 1; }

      OUT_DIR="${cfg.dataDir}"
      mkdir -p "$OUT_DIR"

      SLUG="daily-brief-$EP_DATE"
      WAV="$OUT_DIR/$SLUG.wav"
      MP3="$OUT_DIR/$SLUG.mp3"

      piper --model ${voiceModel} --output_file "$WAV" < "$TEXT_FILE"
      ffmpeg -y -loglevel error -i "$WAV" -codec:a libmp3lame -qscale:a 4 "$MP3"
      rm -f "$WAV"

      # Prune to the newest N episodes
      # shellcheck disable=SC2012
      ls -1t "$OUT_DIR"/daily-brief-*.mp3 | tail -n +$((${toString cfg.keepEpisodes} + 1)) | while read -r old; do
        rm -f "$old"
      done

      FEED="$OUT_DIR/feed.xml"
      {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">'
        echo '<channel>'
        echo "<title>${cfg.feedTitle}</title>"
        echo "<link>https://${cfg.domain}/</link>"
        echo "<description>${cfg.feedDescription}</description>"
        echo '<language>en-us</language>'
        echo '<itunes:explicit>false</itunes:explicit>'

        # shellcheck disable=SC2012
        ls -1t "$OUT_DIR"/daily-brief-*.mp3 | while read -r ep; do
          BASENAME="$(basename "$ep")"
          EP_TITLE="$BASENAME"
          SIZE="$(stat -c %s "$ep")"
          PUBDATE="$(date -R -r "$ep")"
          echo '<item>'
          echo "<title>$EP_TITLE</title>"
          echo "<guid>https://${cfg.domain}/$BASENAME</guid>"
          echo "<pubDate>$PUBDATE</pubDate>"
          echo "<enclosure url=\"https://${cfg.domain}/$BASENAME\" length=\"$SIZE\" type=\"audio/mpeg\"/>"
          echo '</item>'
        done

        echo '</channel>'
        echo '</rss>'
      } > "$FEED.tmp"
      mv "$FEED.tmp" "$FEED"

      echo "Published $MP3"
      echo "Feed: $OUT_DIR/feed.xml"

      if [ "''${DAILY_BRIEF_PODCAST_SKIP_RESYNC:-}" != "1" ]; then
        systemctl start ipod-sync.service || echo "ipod-sync.service did not run (iPod likely not connected) -- it will pick this episode up on next connect via iopod-prepare" >&2
      fi
    '';
  };

  # Watches the Syncthing-synced vault copy of AIOS/history/daily-briefs/ for
  # new spoken-word scripts and publishes each one exactly once. Runs
  # entirely on david's own pull; nothing outbound from wherever the script
  # is written reaches this host directly.
  #
  # Publish markers are kept in a separate stateDir, not alongside the
  # scripts themselves — the scripts directory is bidirectionally synced by
  # Syncthing, so a marker written there would propagate back out to every
  # other paired device as vault noise.
  watchScript = pkgs.writeShellApplication {
    name = "daily-brief-podcast-watch";
    runtimeInputs = [ publishScript pkgs.coreutils ];
    text = ''
      WATCH_DIR="${cfg.audioScriptDir}"
      STATE_DIR="${cfg.stateDir}/published"
      mkdir -p "$STATE_DIR"

      shopt -s nullglob
      for f in "$WATCH_DIR"/*.audio.txt; do
        base="$(basename "$f" .audio.txt)"

        if ! [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
          echo "skipping $f: expected filename format YYYY-MM-DD.audio.txt" >&2
          continue
        fi

        marker="$STATE_DIR/$base"
        if [ -e "$marker" ]; then
          continue
        fi

        echo "publishing daily brief audio for $base"
        if daily-brief-podcast publish --title "Daily Brief - $base" --text-file "$f" --date "$base"; then
          touch "$marker"
          echo "published $base"
        else
          echo "failed to publish $base -- will retry next tick" >&2
        fi
      done
    '';
  };
in
{
  options.modules.services.media.dailyBriefPodcast = {
    enable = mkEnableOption "Self-hosted podcast feed for the daily brief audio script";

    domain = mkOption {
      type = types.str;
      default = "brief.${config.networking.domain}";
      description = "FQDN the feed and episodes are served at.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/data/media/podcasts/daily-brief";
      description = "Directory holding episode mp3s and feed.xml.";
    };

    owner = mkOption {
      type = types.str;
      description = "User that owns dataDir and runs the publish script.";
    };

    keepEpisodes = mkOption {
      type = types.int;
      default = 3;
      description = "Number of most-recent episodes to retain; older ones are pruned on publish.";
    };

    feedTitle = mkOption {
      type = types.str;
      default = "Daily Brief";
      description = "Podcast feed title.";
    };

    feedDescription = mkOption {
      type = types.str;
      default = "A daily audio rundown of the day ahead.";
      description = "Podcast feed description.";
    };

    audioScriptDir = mkOption {
      type = types.str;
      description = ''
        Directory scanned for spoken-word scripts to publish, synced in from
        the Obsidian vault (e.g. via Syncthing). Filenames must be
        YYYY-MM-DD.audio.txt; anything else is skipped and logged.
      '';
      example = "/data/tristonyoder/home/Documents/Obsidian Vault/AIOS/history/daily-briefs";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/daily-brief-podcast";
      description = "Directory holding publish markers, kept outside audioScriptDir so they don't sync back out as vault noise.";
    };

    watchInterval = mkOption {
      type = types.str;
      default = "*:0/15";
      description = "systemd OnCalendar expression for how often to scan audioScriptDir for new scripts.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ publishScript watchScript ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.owner} ${cfg.owner} -"
      "d ${cfg.stateDir} 0755 ${cfg.owner} ${cfg.owner} -"
      "d ${cfg.stateDir}/published 0755 ${cfg.owner} ${cfg.owner} -"
    ];

    systemd.services.daily-brief-podcast-watch = {
      description = "Scan for new daily-brief audio scripts and publish them as podcast episodes";
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.owner;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "daily-brief-podcast-watch";
        ExecStart = "${watchScript}/bin/daily-brief-podcast-watch";
      };
    };

    systemd.timers.daily-brief-podcast-watch = {
      description = "Periodically scan for new daily-brief audio scripts";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.watchInterval;
        Persistent = true;
        RandomizedDelaySec = "1min";
      };
    };

    modules.services.vHosts.hosts."brief" = {
      virtualHost = cfg.domain;
      rawConfig = true;
      public = false;
      monitor = false;
      shortcut = false;
      displayName = "Daily Brief";
      category = "productivity";
      extraConfig = ''
        root * ${cfg.dataDir}
        file_server
      '';
    };
  };
}
