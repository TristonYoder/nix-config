# Provisional hardware config for Julia-NixBook-Air (MacBook Air 2013).
#
# Filesystems are referenced by label so the install can use this file as-is:
# partition the internal SSD with a vfat ESP labelled BOOT and an ext4 root
# labelled nixos (see configuration.nix header). Replace with the output of
# `nixos-generate-config --show-hardware-config` after first boot if anything
# is missing.
{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # 4-8 GB RAM; compressed swap in RAM instead of a swap partition.
  zramSwap.enable = true;

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
