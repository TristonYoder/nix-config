# NixOS installer ISO for pre-T2 Intel iMacs (2017 and earlier).
#
# The generic installer (Tailscale + key-only SSH, ../installer/common.nix)
# plus Broadcom WiFi that works on either chip family (./broadcom-auto.nix).
#
# Keyboardless install: a local-only module (never committed, see flake.nix)
# adds the WiFi profile, a headscale pre-auth key and the target hostname, so
# the machine boots straight onto WiFi and the tailnet with no one at it.
#
# Build on an x86_64-linux builder (david), from the account holding the file:
#   nix build --impure --refresh \
#     'github:TristonYoder/nix-config#nixosConfigurations.imac-installer.config.system.build.isoImage'
{ lib, ... }:
{
  imports = [
    ../installer/configuration.nix
    ./broadcom-auto.nix
  ];

  # NetworkManager carries the pre-seeded WiFi profile. Don't force
  # networking.wireless off: its wpa_supplicant is NM's backend.
  networking.networkmanager.enable = true;

  # mkOverride 40 beats the mkForce (50) in ../installer/configuration.nix.
  image.baseName = lib.mkOverride 40 "nixos-imac-installer";
}
