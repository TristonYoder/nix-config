# Configuration for Tristons-MacBook-Pro - macOS MacBook Pro (Intel T2)
# Friendly name: Triston's MacBook Pro
# Uses nix-darwin for system configuration

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "Tristons-MacBook-Pro";
  networking.localHostName = "Tristons-MacBook-Pro";
  networking.computerName = "Triston's MacBook Pro";
  
  # =============================================================================
  # USER CONFIGURATION
  # =============================================================================
  
  users.users.tristonyoder = {
    name = "tristonyoder";
    home = "/Users/tristonyoder";
    shell = pkgs.zsh;
  };
}
