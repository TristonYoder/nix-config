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
    ./plex.nix
    ./sunshine.nix
  ];
}
