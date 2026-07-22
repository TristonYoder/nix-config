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

  # Native aarch64-linux build machine (Apple Virtualization framework VM),
  # registered with the Nix daemon automatically. Needed to build aarch64-linux
  # derivations locally — e.g. the stage-plotiphar Pi 5 installer image, since
  # no other host in this repo has aarch64-linux build capability.
  nix.linux-builder.enable = true;
}

