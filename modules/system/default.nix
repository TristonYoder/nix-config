{ ... }:
{
  # Import system modules
  imports = [
    ./core.nix
    ./networking.nix
    ./users.nix
    ./desktop.nix
  ];
}

