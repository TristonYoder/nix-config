{ ... }:
{
  # Import system modules
  imports = [
    ./auto-update.nix
    ./core.nix
    ./networking.nix
    ./users.nix
    ./desktop.nix
  ];
}
