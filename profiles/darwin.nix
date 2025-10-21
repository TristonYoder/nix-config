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
  
  # nix-daemon is now managed unconditionally by nix-darwin when nix.enable is on
  
  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;
  
  # Set primary user for system defaults
  system.primaryUser = "tyoder";
  
  # =============================================================================
  # NIX OPTIMIZATION (Darwin-safe method)
  # =============================================================================
  
  # Use automatic optimization instead of auto-optimise-store (which corrupts store on Darwin)
  nix.optimise.automatic = true;
  
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
    # Nerd Fonts (individual packages in new structure)
    nerd-fonts.fira-code
    nerd-fonts.meslo-lg
    nerd-fonts.roboto-mono
  ];
}

