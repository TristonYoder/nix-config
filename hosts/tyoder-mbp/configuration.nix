# Configuration for tyoder-mbp - macOS MacBook Pro (Apple Silicon)
# Friendly name: Triston's TPCC MacBook Pro
# Uses nix-darwin for system configuration

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "tyoder-mbp";
  networking.localHostName = "tyoder-mbp";
  networking.computerName = "Triston Yoder's MacBook Pro";
  
  # =============================================================================
  # USER CONFIGURATION
  # =============================================================================
  
  users.users.tyoder = {
    name = "tyoder";
    home = "/Users/tyoder";
    shell = pkgs.zsh;
  };
  
  # Set primary user for system defaults
  system.primaryUser = "tyoder";
}

