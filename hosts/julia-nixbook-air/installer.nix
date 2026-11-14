# NixOS installer ISO for Julia-NixBook-Air (MacBook Air 2013, MacBookAir6,x)
#
# Same as the generic installer (Tailscale QR + key-only SSH, see
# ../installer/common.nix) plus the Broadcom wl WiFi driver (./broadcom-wl.nix).
#
# Build (needs an x86_64-linux builder, e.g. david):
#   nix build .#nixosConfigurations.julia-nixbook-air-installer.config.system.build.isoImage --refresh
{ lib, ... }:
{
  imports = [
    ../installer/configuration.nix
    ./broadcom-wl.nix
  ];

  # installation-cd-minimal enables wpa_supplicant; nmtui is easier for
  # joining WiFi by hand on first boot.
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  # mkOverride 40 beats the mkForce (50) in ../installer/configuration.nix.
  image.baseName = lib.mkOverride 40 "nixos-julia-nixbook-air-installer";
}
