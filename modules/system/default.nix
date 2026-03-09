{ ... }:
{
  # Import system modules
  imports = [
    ./auto-update.nix
    ./core.nix
    ./networking.nix
    ./users.nix
    ./desktop.nix
    ./multiseat.nix
    ./virtualization.nix
  ];
}
