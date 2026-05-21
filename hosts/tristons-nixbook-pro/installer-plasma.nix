# NixOS Plasma 6 installer ISO for tristons-nixbook-pro (T2 MacBook Pro)
#
# Full KDE Plasma 6 desktop with WiFi firmware fetched from macOS Sonoma at
# build time via Asahi extraction scripts. No --impure flag required.
# Connect to WiFi via NetworkManager tray applet, then install from Konsole.
#
# Build command (from nix-config root on tyoder-mbp):
#
#   export PATH="/nix/var/nix/profiles/default/bin:$PATH"
#   nix build .#nixosConfigurations.tristons-nixbook-pro-installer-plasma.config.system.build.isoImage \
#     --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
#     --option extra-substituters "https://cache.soopy.moe" \
#     --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix")
  ];

  # WiFi firmware fetched from macOS Sonoma installer via Asahi extraction scripts.
  # Fully reproducible — no manual firmware extraction or --impure required.
  hardware.apple-t2.firmware = {
    enable = true;
    version = "sonoma";
  };

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    substituters = lib.mkAfter [ "https://cache.soopy.moe" ];
    trusted-public-keys = lib.mkAfter [
      "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="
    ];
  };

  boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

  isoImage.isoName = lib.mkForce "nixos-t2-macbookpro16-plasma.iso";
}
