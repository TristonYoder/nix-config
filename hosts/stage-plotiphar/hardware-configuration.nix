# PLACEHOLDER — this host has not been physically installed yet.
#
# Replace this file with the real output of `nixos-generate-config
# --show-hardware-config` once booted from the nixos-raspberrypi rpi5
# installer image (see hosts/stage-plotiphar/README.md). Kept buildable in
# the meantime by assuming the partition labels below — use them when
# partitioning the NVMe during the physical install and this file will
# already be correct; if you partition differently, regenerate instead.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];

  boot.initrd.availableKernelModules = [ "nvme" "usbhid" "usb_storage" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "ext4";
  };

  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
  };

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
