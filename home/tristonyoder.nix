# Home Manager configuration for tristonyoder (NixOS)

{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];
  
  # User and home directory
  home.username = "tristonyoder";
  home.homeDirectory = "/home/tristonyoder";
  home.stateVersion = "25.05";
  
  # =============================================================================
  # NIXOS-SPECIFIC PACKAGES
  # =============================================================================
  
  home.packages = with pkgs; [
    # NixOS-specific tools
    # Add any Linux-specific packages here
  ];
  
  # =============================================================================
  # NIXOS-SPECIFIC CONFIGURATION
  # =============================================================================
  
  # Additional configuration for NixOS can go here
  # For example, GTK themes, desktop environment settings, etc.
  
  # GTK theme configuration (if using a desktop environment)
  # gtk = {
  #   enable = true;
  #   theme = {
  #     name = "Adwaita-dark";
  #     package = pkgs.gnome.gnome-themes-extra;
  #   };
  # };
}

