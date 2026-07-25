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

