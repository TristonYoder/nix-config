# Configuration for Tristons-MacBook-Pro-Intel - macOS MacBook Pro (Intel T2)
# Friendly name: Triston's Intel MacBook Pro
# Uses nix-darwin for system configuration
#
# Renamed from Tristons-MacBook-Pro when the Apple Silicon MacBook took that
# name. On first rebuild of this machine, pass the flake attr explicitly so the
# hostname gets updated:
#   sudo darwin-rebuild switch --refresh --flake 'github:TristonYoder/nix-config#Tristons-MacBook-Pro-Intel'

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "Tristons-MacBook-Pro-Intel";
  networking.localHostName = "Tristons-MacBook-Pro-Intel";
  networking.computerName = "Triston's Intel MacBook Pro";

  # =============================================================================
  # USER CONFIGURATION
  # =============================================================================

  users.users.tristonyoder = {
    name = "tristonyoder";
    home = "/Users/tristonyoder";
    shell = pkgs.zsh;
  };

  # Set primary user for system defaults
  system.primaryUser = "tristonyoder";
}
