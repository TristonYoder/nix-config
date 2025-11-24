# Configuration for tristons-desk - NixOS Desktop
# Minimal desktop setup for workstation use

{ config, pkgs, lib, ... }:
{
  # Import common configuration and desktop profile
  # Note: Module imports (./modules) are handled by flake.nix
  # The desktop profile (../../profiles/desktop.nix) enables minimal desktop services
  
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "tristons-desk";
  networking.domain = "theyoder.family";
  system.stateVersion = "25.05";

  # =============================================================================
  # HOST-SPECIFIC SETTINGS
  # =============================================================================
  
  # All module enables are set in ../../profiles/desktop.nix
  # You can override any profile settings here if needed for this specific host
  
  # Example: Enable NVIDIA if this desktop has an NVIDIA GPU
  # modules.hardware.nvidia.enable = true;
  
  # Example: Enable Syncthing for file sync
  # modules.services.storage.syncthing.enable = true;
  
  # =============================================================================
  # ADDITIONAL PACKAGES FOR DESKTOP
  # =============================================================================
  
  environment.systemPackages = with pkgs; [
    # Desktop-specific packages
    firefox
    vlc
    
    # Development tools
    vscode
  ];
}

