{ ... }:
{
  # Import media service modules
  imports = [
    ./immich.nix
    ./jellyfin.nix
    ./jellyplex-watched.nix
    ./jellyseerr.nix
    ./plex.nix
    ./sunshine.nix
  ];
}
