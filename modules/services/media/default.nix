{ ... }:
{
  # Import media service modules
  imports = [
    ./immich.nix
    ./jellyfin.nix
    ./jellyseerr.nix
    ./sunshine.nix
  ];
}

