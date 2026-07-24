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

  # =============================================================================
  # LINUX BUILDER
  # =============================================================================

  # nix-darwin's built-in linux-builder VM. On Apple Silicon this builds
  # aarch64-linux natively (no emulation) — needed to build the
  # nixosConfigurations.installer-aarch64 ISO, which no other host in the
  # fleet can currently build.
  nix.linux-builder.enable = true;
}

