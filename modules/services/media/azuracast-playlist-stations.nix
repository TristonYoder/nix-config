# Auto-provisions an AzuraCast station for every m3u file in a directory
# (e.g. Plexamp/Jellyfin-generated mixes). Each station's auto-created
# "default" playlist is switched to a remote_url/playlist source pointing
# straight at the m3u file, so Liquidsoap streams it directly - no AzuraCast
# media-library scan involved, and it picks up daily file regeneration on its
# own via Liquidsoap's file-watch reload. See azuracast.nix for why the
# container mounts each library at the same absolute path as the host (so
# these paths resolve with no rewriting).
#
# Optionally also mirrors every AzuraCast station into Navidrome as an
# Internet Radio Station (Subsonic API), matched by stream URL so it never
# touches entries added/renamed by hand - it only fills in the ones missing.
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.azuracastPlaylistStations;
in
{
  options.modules.services.media.azuracastPlaylistStations = {
    enable = mkEnableOption "Auto-create AzuraCast stations from m3u files in a directory";

    azuracastUrl = mkOption {
      type = types.str;
      default = "http://localhost:${toString config.modules.services.media.azuracast.httpPort}";
      description = "Base URL of the AzuraCast API";
    };

    apiKeyFile = mkOption {
      type = types.str;
      description = "Path to a file containing the AzuraCast API key";
    };

    m3uDir = mkOption {
      type = types.str;
      default = "/data/media/Music/m3u/playlist";
      description = "Directory scanned for m3u files. Each one becomes its own station.";
    };

    excludeFiles = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "m3u file names (as they appear in m3uDir, including .m3u extension) to skip.";
    };

    schedule = mkOption {
      type = types.str;
      default = "hourly";
      description = "systemd OnCalendar expression for how often to scan for new m3u files";
    };

    navidromeSync = {
      enable = mkEnableOption "Mirror every AzuraCast station into Navidrome as an Internet Radio Station";

      url = mkOption {
        type = types.str;
        default = "http://localhost:${toString config.modules.services.media.navidrome.port}";
        description = "Base URL of the Navidrome Subsonic API";
      };

      user = mkOption {
        type = types.str;
        description = "Navidrome username used to manage Internet Radio Stations. Must have the admin role.";
      };

      passwordFile = mkOption {
        type = types.str;
        description = "Path to a file containing that Navidrome user's password";
      };
    };
  };

  config = mkIf cfg.enable {
    systemd.services.azuracast-playlist-stations = {
      description = "Create AzuraCast stations for any new m3u file in ${cfg.m3uDir}";
      after = [ "network-online.target" "docker-azuracast.service" ]
        ++ optional cfg.navidromeSync.enable "navidrome.service";
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "azuracast-playlist-stations" (''
          set -euo pipefail
          URL="${cfg.azuracastUrl}"
          API_KEY=$(cat "${cfg.apiKeyFile}")

          existing_shortnames=$(${pkgs.curl}/bin/curl -sf -H "X-API-Key: $API_KEY" "$URL/api/admin/stations" \
            | ${pkgs.jq}/bin/jq -r '.[].short_name')

          shopt -s nullglob
          for file in "${cfg.m3uDir}"/*.m3u "${cfg.m3uDir}"/*.M3U; do
            base="$(basename "$file")"

            skip=false
            for excl in ${concatStringsSep " " (map lib.escapeShellArg cfg.excludeFiles)}; do
              if [ "$base" = "$excl" ]; then
                skip=true
                break
              fi
            done
            if [ "$skip" = true ]; then
              continue
            fi

            name="''${base%.*}"
            shortname=$(echo "$name" | ${pkgs.coreutils}/bin/tr '[:upper:]' '[:lower:]' \
              | ${pkgs.gnused}/bin/sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')

            if echo "$existing_shortnames" | grep -qxF "$shortname"; then
              continue
            fi

            echo "Creating AzuraCast station for new playlist: $name ($shortname)"

            station_json=$(${pkgs.jq}/bin/jq -n --arg name "$name" --arg short_name "$shortname" \
              '{name: $name, short_name: $short_name, frontend_type: "icecast", backend_type: "liquidsoap", is_enabled: true, enable_public_page: true}')

            station_id=$(${pkgs.curl}/bin/curl -sf -X POST -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
              -d "$station_json" "$URL/api/admin/stations" | ${pkgs.jq}/bin/jq -r '.id')

            if [ -z "$station_id" ] || [ "$station_id" = "null" ]; then
              echo "Error: failed to create station for $name" >&2
              continue
            fi

            playlist_id=$(${pkgs.curl}/bin/curl -sf -H "X-API-Key: $API_KEY" "$URL/api/station/$station_id/playlists" \
              | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "default") | .id')

            playlist_json=$(${pkgs.jq}/bin/jq -n --arg url "$file" \
              '{source: "remote_url", remote_type: "playlist", remote_url: $url}')

            ${pkgs.curl}/bin/curl -sf -X PUT -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
              -d "$playlist_json" "$URL/api/station/$station_id/playlist/$playlist_id" > /dev/null

            ${pkgs.curl}/bin/curl -sf -X POST -H "X-API-Key: $API_KEY" "$URL/api/station/$station_id/restart" > /dev/null

            echo "Station '$name' created and streaming from $file"

            existing_shortnames="$existing_shortnames"$'\n'"$shortname"
          done
        ''
        + optionalString cfg.navidromeSync.enable ''
          NAV_URL="${cfg.navidromeSync.url}"
          NAV_USER="${cfg.navidromeSync.user}"
          NAV_PASS=$(cat "${cfg.navidromeSync.passwordFile}")
          NAV_SALT=$(${pkgs.openssl}/bin/openssl rand -hex 6)
          NAV_TOKEN=$(printf '%s%s' "$NAV_PASS" "$NAV_SALT" | ${pkgs.coreutils}/bin/md5sum | ${pkgs.coreutils}/bin/cut -d' ' -f1)
          nav_curl() {
            ${pkgs.curl}/bin/curl -sf -G "$@" \
              --data-urlencode "u=$NAV_USER" --data-urlencode "t=$NAV_TOKEN" --data-urlencode "s=$NAV_SALT" \
              --data-urlencode "v=1.16.1" --data-urlencode "c=nix-config" --data-urlencode "f=json"
          }

          navidrome_stream_urls=$(nav_curl "$NAV_URL/rest/getInternetRadioStations.view" \
            | ${pkgs.jq}/bin/jq -r '.["subsonic-response"].internetRadioStations.internetRadioStation[]?.streamUrl')

          ${pkgs.curl}/bin/curl -sf "$URL/api/stations" | ${pkgs.jq}/bin/jq -c '.[]' | while read -r station; do
            station_name=$(echo "$station" | ${pkgs.jq}/bin/jq -r '.name')
            listen_url=$(echo "$station" | ${pkgs.jq}/bin/jq -r '.listen_url')

            if [ -z "$listen_url" ] || [ "$listen_url" = "null" ]; then
              continue
            fi
            if echo "$navidrome_stream_urls" | grep -qxF "$listen_url"; then
              continue
            fi

            echo "Registering '$station_name' in Navidrome..."
            nav_curl "$NAV_URL/rest/createInternetRadioStation.view" \
              --data-urlencode "name=$station_name" --data-urlencode "streamUrl=$listen_url" > /dev/null
          done
        '');
      };
    };

    systemd.timers.azuracast-playlist-stations = {
      description = "Periodic scan for new m3u files in ${cfg.m3uDir}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        OnBootSec = "5m";
        Persistent = true;
      };
    };
  };
}
