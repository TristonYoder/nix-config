{ ... }:
{
  # Import hardware modules
  imports = [
    ./nvidia.nix
    ./boot.nix
    ./display-resolution.nix
    ./t2-suspend.nix
  ];
}

