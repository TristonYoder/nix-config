# Common configuration shared across all hosts
# This file contains settings that should be consistent across all machines
# Individual hosts can override these settings in their own configuration.nix

{ config, pkgs, lib, nixpkgs-unstable, ... }:

let
  pkgs-unstable = import nixpkgs-unstable {
    system = pkgs.system;
    config.allowUnfree = true;
  };
in
{
  # =============================================================================
  # NIX SETTINGS
  # =============================================================================

  networking.domain = lib.mkDefault "theyoder.family";

  nix = {
    # Enable flakes and nix-command
    settings = {
      experimental-features = [ "nix-command" "flakes" ];

      # Trusted users for nix commands
      trusted-users = [ "root" "@wheel" ];
    };

    # Note: auto-optimise-store is configured per-platform:
    # - NixOS: common/linux.nix uses nix.settings.auto-optimise-store
    # - Darwin: profiles/darwin.nix uses nix.optimise.automatic
    # Note: Automatic garbage collection is configured in modules/system/core.nix
  };

  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;

  # Allow insecure packages for specific applications
  nixpkgs.config.permittedInsecurePackages = [
    "electron-35.7.5"  # Required for gfn-electron (GeForce Now)
    "olm-3.2.16"       # Required for Matrix communication bridges
  ];

  # =============================================================================
  # LOCALE & TIME (can be overridden per-host)
  # =============================================================================

  # Time zone (works on both NixOS and Darwin)
  time.timeZone = lib.mkDefault "America/Indiana/Indianapolis";

  # Note: i18n settings are NixOS-only and should be set in server.nix/desktop.nix/edge.nix

  # =============================================================================
  # COMMON PACKAGES
  # =============================================================================

  environment.systemPackages = with pkgs; [
    # Essential tools
    git
    nano
    wget
    curl
    htop
    tree

    # Compression & archiving
    unzip
    zip

    # Network tools
    dig
    nmap

    # AI tools (from unstable for latest features)
    pkgs-unstable.gemini-cli
    pkgs-unstable.claude-code
    pkgs-unstable.codex

    # Note: Linux-only utilities (pciutils, usbutils) are in profiles/server.nix
  ];
  
  # =============================================================================
  # COMMON PROGRAMS
  # =============================================================================
  
  programs = {
    # Enable zsh globally
    zsh.enable = true;
  };
  
  # Note: programs.git is NixOS-only and is configured in common/linux.nix
  # Note: security.sudo is NixOS-only and is configured in common/linux.nix
}
