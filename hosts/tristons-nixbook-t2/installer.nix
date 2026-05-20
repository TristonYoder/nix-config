# NixOS installer ISO for tristons-nixbook-t2 (T2 MacBook Pro)
#
# WiFi firmware is fetched from a macOS Sonoma installer image at build time
# using the Asahi Linux extraction scripts (via nixos-hardware). No manual
# firmware extraction or --impure flag required.
#
# Build command (from nix-config root on tyoder-mbp):
#
#   export PATH="/nix/var/nix/profiles/default/bin:$PATH"
#   nix build .#nixosConfigurations.tristons-nixbook-t2-installer.config.system.build.isoImage \
#     --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
#     --option extra-substituters "https://cache.soopy.moe" \
#     --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

{ lib, modulesPath, ... }:
{
  imports = [
    # Minimal installer base: no GUI, gives a shell with nixos-install available
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # WiFi firmware fetched from macOS Sonoma installer via Asahi extraction scripts.
  # Fully reproducible — no manual firmware extraction or --impure required.
  hardware.apple-t2.firmware = {
    enable = true;
    version = "sonoma";
  };

  # Soopy.moe binary cache so the live environment can fetch T2 kernel packages
  # without compiling from source.
  nix.settings = {
    substituters = lib.mkAfter [ "https://cache.soopy.moe" ];
    trusted-public-keys = lib.mkAfter [
      "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="
    ];
  };

  # Trackpad regression fix carried over from the installed system config
  boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

  isoImage.isoName = lib.mkForce "nixos-t2-macbookpro16.iso";
}
