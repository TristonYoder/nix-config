# NixOS Plasma 6 installer ISO for tristons-nixbook-t2 (T2 MacBook Pro)
#
# Full KDE Plasma 6 desktop with WiFi firmware baked in.
# Connect to WiFi via NetworkManager tray applet, then install from Konsole.
#
# Build command (from nix-config root on tyoder-mbp):
#
#   export PATH="/nix/var/nix/profiles/default/bin:$PATH"
#   age -d -i ~/.ssh/agenix secrets/t2-wifi-firmware.age > /tmp/t2-wifi-firmware.tar.gz
#   nix build .#nixosConfigurations.tristons-nixbook-t2-installer-plasma.config.system.build.isoImage \
#     --impure \
#     --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
#     --option extra-substituters "https://cache.soopy.moe" \
#     --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

{ pkgs, lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix")
  ];

  # WiFi firmware baked into the ISO image.
  # --impure is required because this references a path outside the flake.
  hardware.firmware = [
    (pkgs.runCommandNoCC "brcm-t2-firmware" { } ''
      mkdir -p $out/lib/firmware/brcm
      tar xzf ${builtins.path {
        path = /tmp/t2-wifi-firmware.tar.gz;
        name = "t2-wifi-firmware.tar.gz";
      }} -C $out/lib/firmware/brcm/
    '')
  ];

  nix.settings = {
    substituters = lib.mkAfter [ "https://cache.soopy.moe" ];
    trusted-public-keys = lib.mkAfter [
      "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="
    ];
  };

  boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

  isoImage.isoName = lib.mkForce "nixos-t2-macbookpro16-plasma.iso";
}
