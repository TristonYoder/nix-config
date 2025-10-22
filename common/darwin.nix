# Common configuration for all macOS/Darwin hosts
# This file contains settings shared across all Darwin machines

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # DARWIN-SPECIFIC SETTINGS
  # =============================================================================
  
  # macOS system defaults are primarily configured in profiles/darwin.nix
  # and home-manager (home/tyoder.nix)
  
  # =============================================================================
  # DARWIN-SPECIFIC PACKAGES
  # =============================================================================
  
  # Add any macOS-specific system packages here
  # Most macOS apps are managed via Homebrew in home-manager
  environment.systemPackages = with pkgs; [
    # Add Darwin-specific packages here if needed
  ];
}

