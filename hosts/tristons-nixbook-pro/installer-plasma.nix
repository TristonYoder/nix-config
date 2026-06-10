# NixOS Plasma 6 installer ISO for tristons-nixbook-pro (T2 MacBook Pro)
#
# Full KDE Plasma 6 desktop with Calamares graphical installer.
# WiFi firmware fetched from macOS Sonoma at build time — connect via
# the NetworkManager tray applet, then run 't2-install' in Konsole.
#
# CI builds this on manual dispatch via .github/workflows/build-t2-iso.yml.
# Manual build (from nix-config root):
#
#   nix build .#nixosConfigurations.tristons-nixbook-pro-installer-plasma.config.system.build.isoImage \
#     --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
#     --option extra-substituters "https://cache.soopy.moe" \
#     --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix")
    ./installer-common.nix
  ];

  image.fileName = lib.mkForce "nixos-t2-macbookpro16-plasma.iso";
}
