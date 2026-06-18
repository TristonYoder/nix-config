# Common configuration for all Linux/NixOS hosts
# This file contains settings shared across all NixOS machines

{ config, pkgs, lib, self, ... }:

{
  # =============================================================================
  # NIX SETTINGS (NixOS specific)
  # =============================================================================
  
  # Bake the git commit SHA into the running system so update-notifier can
  # compare against the latest deployed SHA from the GitHub Actions API.
  system.configurationRevision = self.rev or "dirty";

  nix.settings = {
    # Enable store optimization (safe on NixOS)
    auto-optimise-store = true;
    trusted-substituters = [ "ssh-ng://david" ];
    # Allow vmTools (nixos-hardware brcm-firmware, nixpkgs VM tests) to use KVM
    extra-sandbox-paths = [ "/dev/kvm" ];
    system-features = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
  };
  
  # =============================================================================
  # LOCALE (NixOS specific)
  # =============================================================================
  
  i18n = {
    defaultLocale = lib.mkDefault "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = lib.mkDefault "en_US.UTF-8";
      LC_IDENTIFICATION = lib.mkDefault "en_US.UTF-8";
      LC_MEASUREMENT = lib.mkDefault "en_US.UTF-8";
      LC_MONETARY = lib.mkDefault "en_US.UTF-8";
      LC_NAME = lib.mkDefault "en_US.UTF-8";
      LC_NUMERIC = lib.mkDefault "en_US.UTF-8";
      LC_PAPER = lib.mkDefault "en_US.UTF-8";
      LC_TELEPHONE = lib.mkDefault "en_US.UTF-8";
      LC_TIME = lib.mkDefault "en_US.UTF-8";
    };
  };
  
  # =============================================================================
  # LINUX-SPECIFIC PACKAGES
  # =============================================================================
  
  environment.systemPackages = with pkgs; [
    # System utilities (Linux-only)
    pciutils
    usbutils
  ];
  
  # =============================================================================
  # PROGRAMS
  # =============================================================================
  
  programs = {
    # Enable git system-wide
    git.enable = true;
  };
  
  # =============================================================================
  # SECURITY
  # =============================================================================
  
  # Enable sudo
  security.sudo.enable = lib.mkDefault true;

  # =============================================================================
  # BOOT CONFIGURATION
  # =============================================================================

  boot = {
    # Reduce kernel log noise on all Linux hosts
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "boot.shell_on_fail"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
    loader.timeout = 2;
  };
}
