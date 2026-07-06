{ ... }:
{
  # Import media service modules
  imports = [
    ./azuracast.nix
    ./beets.nix
    ./feishin.nix
    ./immich.nix
    ./jellyfin.nix
    ./jellyplex-watched.nix
    ./jellyseerr.nix
    ./music-dedup.nix
    ./navidrome.nix
    ./plex.nix
    ./sunshine.nix
  ];
}
