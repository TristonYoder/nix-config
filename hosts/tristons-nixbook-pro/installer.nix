# NixOS minimal installer ISO for tristons-nixbook-pro (T2 MacBook Pro)
#
# WiFi firmware is fetched from macOS Sonoma at build time via nixos-hardware
# Asahi extraction scripts. No --impure flag required.
#
# The 't2-install' command in the live shell automates partitioning, mounting,
# and nixos-install. See install.sh for the full script.
#
# CI builds this automatically via .github/workflows/build-t2-iso.yml.
# Manual build (from nix-config root):
#
#   nix build .#nixosConfigurations.tristons-nixbook-pro-installer.config.system.build.isoImage \
#     --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
#     --option extra-substituters "https://cache.soopy.moe" \
#     --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ./installer-common.nix
  ];

  image.fileName = lib.mkForce "nixos-t2-macbookpro16.iso";
}
