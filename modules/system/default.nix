{ ... }:
{
  # Import system modules
  imports = [
    ./auto-update.nix
    ./core.nix
    ./krdp.nix
    ./networking.nix
    ./users.nix
    ./desktop.nix
    ./nix-cache.nix
  ];
}
