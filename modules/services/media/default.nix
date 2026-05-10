{ ... }:
{
  # Import media service modules
  imports = [
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
