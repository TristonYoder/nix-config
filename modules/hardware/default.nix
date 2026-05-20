{ ... }:
{
  # Import hardware modules
  imports = [
    ./nvidia.nix
    ./boot.nix
    ./display-resolution.nix
    ./apple-t2.nix
  ];
}

