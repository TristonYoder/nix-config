# Keeps an AzuraCast "songs" playlist in sync with a daily-regenerated M3U file
# (e.g. a Plexamp/Jellyfin "Daily Discovery" mix). AzuraCast's own playlist
# import matches files by path relative to the station's media storage root,
# so the M3U (which contains absolute host paths under musicLibrary) has its
# prefix stripped before being uploaded.
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.azuracastPlaylistSync;
in
{
  options.modules.services.media.azuracastPlaylistSync = {
    enable = mkEnableOption "Daily AzuraCast playlist sync from an M3U file";

    azuracastUrl = mkOption {
      type = types.str;
      default = "http://localhost:${toString config.modules.services.media.azuracast.httpPort}";
      description = "Base URL of the AzuraCast API";
    };

    apiKeyFile = mkOption {
      type = types.str;
      description = "Path to a file containing the AzuraCast API key";
    };

    stationShortName = mkOption {
      type = types.str;
      description = "Short name (shortcode) of the AzuraCast station to update";
    };

    playlistName = mkOption {
      type = types.str;
      description = "Name of the station playlist to replace with the M3U's contents";
    };

    m3uFile = mkOption {
      type = types.str;
      description = "Path to the source M3U file (updated externally, e.g. daily by Plexamp/Jellyfin)";
    };

    musicLibrary = mkOption {
      type = types.str;
      default = "/data/media/Music";
      description = ''
        Root of the music library as referenced by paths inside m3uFile. Stripped
        from each entry so the remainder matches the path relative to the
        station's media storage location root.
      '';
    };

    schedule = mkOption {
      type = types.str;
      default = "04:00";
      description = "systemd OnCalendar expression for when to run the sync";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.azuracast-playlist-sync = {
      description = "Sync AzuraCast playlist '${cfg.playlistName}' from ${cfg.m3uFile}";
      after = [ "network-online.target" "docker-azuracast.service" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "azuracast-playlist-sync" ''
          set -euo pipefail
          URL="${cfg.azuracastUrl}"
          API_KEY=$(cat "${cfg.apiKeyFile}")
          RELATIVE_M3U=$(mktemp)
          trap 'rm -f "$RELATIVE_M3U"' EXIT

          STATION_ID=$(${pkgs.curl}/bin/curl -sf -H "X-API-Key: $API_KEY" "$URL/api/admin/stations" \
            | ${pkgs.jq}/bin/jq -r --arg name "${cfg.stationShortName}" '.[] | select(.short_name == $name) | .id')
          if [ -z "$STATION_ID" ]; then
            echo "Error: station '${cfg.stationShortName}' not found" >&2
            exit 1
          fi

          PLAYLIST_ID=$(${pkgs.curl}/bin/curl -sf -H "X-API-Key: $API_KEY" "$URL/api/station/$STATION_ID/playlists" \
            | ${pkgs.jq}/bin/jq -r --arg name "${cfg.playlistName}" '.[] | select(.name == $name) | .id')
          if [ -z "$PLAYLIST_ID" ]; then
            echo "Error: playlist '${cfg.playlistName}' not found on station ${cfg.stationShortName}" >&2
            exit 1
          fi

          ${pkgs.gnused}/bin/sed "s|^${cfg.musicLibrary}/||" "${cfg.m3uFile}" > "$RELATIVE_M3U"

          echo "Emptying playlist $PLAYLIST_ID..."
          ${pkgs.curl}/bin/curl -sf -X PUT -H "X-API-Key: $API_KEY" \
            "$URL/api/station/$STATION_ID/playlist/$PLAYLIST_ID/empty" > /dev/null

          echo "Importing ${cfg.m3uFile}..."
          RESULT=$(${pkgs.curl}/bin/curl -sf -X POST -H "X-API-Key: $API_KEY" \
            -F "playlist_file=@$RELATIVE_M3U" \
            "$URL/api/station/$STATION_ID/playlist/$PLAYLIST_ID/import")
          echo "$RESULT" | ${pkgs.jq}/bin/jq -r '.formatted_message // .message'
        '';
      };
    };

    systemd.timers.azuracast-playlist-sync = {
      description = "Daily AzuraCast playlist sync from ${cfg.m3uFile}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
  };
}
