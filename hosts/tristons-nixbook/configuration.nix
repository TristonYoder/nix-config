# Configuration for tristons-nixbook - NixOS Laptop
# Desktop/workstation setup for laptop use

{ config, pkgs, lib, ... }:
{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "tristons-nixbook";
  system.stateVersion = "25.05";

  # =============================================================================
  # HOST-SPECIFIC SETTINGS
  # =============================================================================

  # All module enables are set in ../../profiles/desktop.nix
  # Override any profile settings here if needed for this specific host

  # Example: Enable Syncthing for file sync
  # modules.services.storage.syncthing.enable = true;

  # =============================================================================
  # ADDITIONAL PACKAGES FOR LAPTOP
  # =============================================================================

  environment.systemPackages = with pkgs; [
    # Desktop applications
    firefox
    vlc

    # Development tools
    vscode
  ];
}
