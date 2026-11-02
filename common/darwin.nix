# Common configuration for all macOS/Darwin hosts
# This file contains settings shared across all Darwin machines

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # NIX-DARWIN SYSTEM SETTINGS
  # =============================================================================
  
  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 5;

  # Back up pre-existing files (e.g. brew's ~/.zprofile) instead of failing
  # activation when Home Manager wants to manage a path that already exists.
  # NixOS hosts already set this per-host in flake.nix; darwin hosts inherit it here.
  home-manager.backupFileExtension = "backup";

  # =============================================================================
  # HOST-SPECIFIC SETTINGS
  # =============================================================================
  
  # macOS-specific system packages
  environment.systemPackages = with pkgs; [
    # Additional packages beyond darwin profile
  ];

  # =============================================================================
  # NIX BUILD CACHE
  # =============================================================================

  # All macOS hosts have Tailscale — pull from david's binary cache to avoid
  # re-downloading store paths the CI build-offline-closures job already built.
  nix.settings.substituters = [ "https://nix-cache.theyoder.family" ];
  nix.settings.trusted-substituters = [ "https://nix-cache.theyoder.family" ];
  nix.settings.trusted-public-keys = [ "nix-cache.theyoder.family:NgpfqkeBWGMBuRI6uaxIqVTPEPRtyd4DcTJcvAFv4T4=" ];

  # =============================================================================
  # MACOS SYSTEM PREFERENCES
  # =============================================================================
  
  # Keyboard settings
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = false;
  };
  
  # Trackpad settings
  system.defaults.trackpad = {
    Clicking = true;  # Enable tap to click
    TrackpadRightClick = true;
    TrackpadThreeFingerDrag = false;
  };
  
  # Dock settings (additional to home-manager settings)
  system.defaults.dock = {
    autohide = false;
    orientation = "bottom";
    show-recents = false;
    tilesize = 36;
  };
  
  # Finder settings
  system.defaults.finder = {
    AppleShowAllExtensions = true;
    ShowPathbar = true;
    FXEnableExtensionChangeWarning = false;
  };
  
  # Global settings
  system.defaults.NSGlobalDomain = {
    AppleKeyboardUIMode = 3;
    ApplePressAndHoldEnabled = false;
    InitialKeyRepeat = 15;
    KeyRepeat = 1;
    
    # Enable dark mode
    AppleInterfaceStyle = "Dark";
    
    # Disable automatic capitalization
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticDashSubstitutionEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSAutomaticQuoteSubstitutionEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
  };
}
