{ ... }:
{
  # Import system modules
  imports = [
    ./auto-update.nix
    ./core.nix
    ./networking.nix
    ./nix-cache-client.nix
    ./remote-builder.nix
    ./users.nix
    ./desktop.nix
  ];
}
