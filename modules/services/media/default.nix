{ ... }:
{
  # Import media service modules
  imports = [
    ./azuracast.nix
    ./azuracast-playlist-stations.nix
    ./beets.nix
    ./daily-brief-podcast.nix
    ./feishin.nix
    ./immich.nix
    ./jellyfin.nix
    ./jellyplex-watched.nix
    ./jellyseerr.nix
    ./music-dedup.nix
    ./kavita.nix
    ./navidrome.nix
    ./plex.nix
    ./sunshine.nix
  ];
}
