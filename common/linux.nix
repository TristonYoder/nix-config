# Common configuration for all Linux/NixOS hosts
# This file contains settings shared across all NixOS machines

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # NIX SETTINGS (NixOS specific)
  # =============================================================================
  
  nix.settings = {
    # Enable store optimization (safe on NixOS)
    auto-optimise-store = true;
    trusted-substituters = [ "ssh-ng://david" ];
  } // lib.optionalAttrs (lib.any (m: lib.hasPrefix "kvm" m) config.boot.kernelModules) {
    # Only expose /dev/kvm in the sandbox on hosts that actually have it (bare-metal with kvm-amd/kvm-intel).
    # VMs (e.g. pits/Hyper-V) lack /dev/kvm and fail the build if this is set.
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
