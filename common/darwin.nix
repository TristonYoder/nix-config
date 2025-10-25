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
  
  # =============================================================================
  # HOST-SPECIFIC SETTINGS
  # =============================================================================
  
  # macOS-specific system packages
  environment.systemPackages = with pkgs; [
    # Additional packages beyond darwin profile
  ];
  
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
