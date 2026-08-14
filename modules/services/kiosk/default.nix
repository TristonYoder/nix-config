{ ... }:
{
  # Import kiosk service modules
  imports = [
    ./browser-kiosk.nix
    ./cec-bridge.nix
  ];
}
