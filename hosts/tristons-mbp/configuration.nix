# Configuration for Tristons-MacBook-Pro - macOS MacBook Pro (Apple Silicon, M5 Pro)
# Friendly name: Triston's MacBook Pro
# Uses nix-darwin for system configuration

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "Tristons-MacBook-Pro";
  networking.localHostName = "Tristons-MacBook-Pro";
  networking.computerName = "Triston’s MacBook Pro";

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

  # =============================================================================
  # LINUX BUILDER
  # =============================================================================

  # Native aarch64-linux build machine (Apple Virtualization framework VM),
  # registered with the Nix daemon automatically. Needed to build aarch64-linux
  # derivations locally — e.g. nixosConfigurations.installer-aarch64 and the
  # stage-plotiphar Pi 5 installer/VM images — since no other host in this
  # repo has aarch64-linux build capability outside of david's QEMU
  # emulation (slower, used mainly by CI).
  nix.linux-builder.enable = true;
  # Default (20GB) fills up fast building ISOs (kernel + X11 + Chromium
  # closures) and needs a manual `nix-collect-garbage -d` on the builder
  # between builds otherwise — bump it so iteration doesn't require that.
  nix.linux-builder.config = {
    virtualisation.darwin-builder.diskSize = 61440; # 60GB
  };
}
