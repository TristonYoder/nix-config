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

  # Enable automatic display resolution detection for Plymouth
  modules.hardware.displayResolution.enable = true;

  boot = {
    plymouth = {
      enable = true;
      theme = "colorful";
      themePackages = with pkgs; [
        # By default we would install all themes
        (adi1090x-plymouth-themes.override {
          selected_themes = [ "colorful" ];
        })
      ];
      # Configure Plymouth to use native resolution without scaling
      extraConfig = ''
        [Daemon]
        Theme=colorful
        ShowDelay=0
        DeviceTimeout=5
      '';
    };

    # Enable "Silent boot"
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
    # Hide the OS choice for bootloaders.
    # It's still possible to open the bootloader list by pressing any key
    # It will just not appear on screen unless a key is pressed
    loader.timeout = 2;
  };
}

