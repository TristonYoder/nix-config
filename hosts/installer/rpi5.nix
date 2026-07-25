# Raspberry Pi 5 (CM5/Pi 5) barebones installer sdImage. Boots directly from
# an SD card/NVMe — no installation-cd-minimal.nix involved, and no
# Pi-specific hardware handling of our own: raspberry-pi-5.base (imported at
# the flake.nix level, from the nixos-raspberrypi flake — same one used by
# the stage-plotiphar kiosk host on the host/plotiphar branch) covers the
# Pi 5's firmware/bootloader/kernel needs.
#
# Build (from a NixOS host, e.g. david):
#   nix build .#nixosConfigurations.installer-rpi5.config.system.build.sdImage --refresh
{ lib, ... }:
{
  imports = [ ./common.nix ];

  networking.hostName = lib.mkForce "nixos-installer-rpi5";

  # Same "nixos-installer-<label>" naming convention as the x86_64/aarch64
  # ISOs (hosts/installer/configuration.nix) — the actual output filename is
  # this plus a nixos-raspberrypi-added compression suffix, e.g.
  # nixos-installer-rpi5.img.zst. mkForce needed: nixos-raspberrypi's own
  # flake.nix sets image.baseName (which sdImage.imageBaseName aliases to)
  # at normal priority.
  sdImage.imageBaseName = lib.mkForce "nixos-installer-rpi5";
}
