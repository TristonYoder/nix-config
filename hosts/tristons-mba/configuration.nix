# Configuration for Tristons-MacBook-Air - macOS MacBook Air (Apple Silicon, M3, 16GB)
# Friendly name: Triston's MacBook Air
# Same setup as Tristons-MacBook-Pro (hosts/tristons-mbp), minus the linux-builder VM.

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "Tristons-MacBook-Air";
  networking.localHostName = "Tristons-MacBook-Air";
  networking.computerName = "Triston’s MacBook Air";

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

  # No nix.linux-builder here: the MacBook Pro already provides local
  # aarch64-linux builds, and the VM's 60GB disk + RAM are a poor fit for
  # a 16GB / 256GB Air.
}
