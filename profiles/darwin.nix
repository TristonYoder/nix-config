# Darwin (macOS) Profile
# Configuration for macOS machines using nix-darwin

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # NIX-DARWIN SYSTEM SETTINGS
  # =============================================================================
  
  # macOS system packages
  environment.systemPackages = with pkgs; [
    # Development tools
    git
    gh
    vim
    
    # Utilities
    wget
    curl
    htop
    tree
  ];
  
  # =============================================================================
  # HOMEBREW INTEGRATION
  # =============================================================================
  
  # Enable Homebrew integration (managed via home-manager)
  # This allows GUI apps that aren't available in nixpkgs
  
  # =============================================================================
  # SYSTEM PREFERENCES
  # =============================================================================
  
  # Auto upgrade nix package and daemon
  services.nix-daemon.enable = true;
  
  # Enable Touch ID for sudo
  security.pam.enableSudoTouchIdAuth = true;
  
  # =============================================================================
  # SHELL CONFIGURATION
  # =============================================================================
  
  # Use zsh as default shell
  programs.zsh.enable = true;
  
  # Set up zsh to work with nix-darwin
  environment.shells = [ pkgs.zsh ];
  
  # =============================================================================
  # FONTS
  # =============================================================================
  
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "Meslo" "RobotoMono" ]; })
  ];
}

