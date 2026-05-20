# Hardware configuration for tristons-nixbook-t2 (2019 T2 MacBook Pro)
#
# TEMPLATE — replace this file with the output of:
#   nixos-generate-config --root /mnt --show-hardware-config
# after partitioning the drive. The fileSystems entries below use partition
# labels; update them to match your actual partition layout.
#
# See hosts/tristons-nixbook-t2/INSTALL.md for the full installation guide.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # T2 NVMe and USB modules required in initrd for early-boot hardware access
  boot.initrd.availableKernelModules = [
    "xhci_pci"    # USB 3.x host controller
    "apple-bce"   # T2 bridge: keyboard, trackpad, audio, Touch Bar
    "nvme"        # NVMe SSD
    "usb_storage"
    "sd_mod"
    "sdhci_pci"   # SD card reader
  ];

  # apple-bce must be in initrd for keyboard input at LUKS prompt (if encrypting)
  boot.initrd.kernelModules = [ "apple-bce" ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # ---------------------------------------------------------------------------
  # FILESYSTEMS — update UUIDs/labels after partitioning
  # Run `blkid` on the live ISO to get partition UUIDs, then use:
  #   device = "/dev/disk/by-uuid/XXXX-XXXX";
  # ---------------------------------------------------------------------------

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Shared EFI partition (created by macOS; /dev/nvme0n1p1 on most T2 Macs)
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/EFI";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
