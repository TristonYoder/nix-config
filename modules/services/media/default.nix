{ ... }:
{
  # Import media service modules
  imports = [
    ./immich.nix
    ./jellyfin.nix
    ./jellyseerr.nix
    ./plex.nix
    ./sunshine.nix
  ];
}
