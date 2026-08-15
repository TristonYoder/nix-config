{ ... }:
{
  # Import system modules
  imports = [
    ./auto-update.nix
    ./core.nix
    ./krdp.nix
    ./networking.nix
    ./users.nix
    ./home-split.nix
    ./desktop.nix
    ./guest-kiosk.nix
    ./nix-cache.nix
  ];
}
