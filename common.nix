# Common configuration shared across all hosts
# This file contains settings that should be consistent across all machines
# Individual hosts can override these settings in their own configuration.nix

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # NIX SETTINGS
  # =============================================================================
  
  nix = {
    # Enable flakes and nix-command
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      
      # Trusted users for nix commands
      trusted-users = [ "root" "@wheel" ];
    };
    
    # Note: Automatic garbage collection is configured in modules/system/core.nix
  };
  
  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;
  
  # =============================================================================
  # LOCALE & TIME (can be overridden per-host)
  # =============================================================================
  
  time.timeZone = lib.mkDefault "America/Indiana/Indianapolis";
} 
// lib.optionalAttrs pkgs.stdenv.isLinux {
  # i18n settings (NixOS only)
  i18n = {
    defaultLocale = lib.mkDefault "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = lib.mkDefault "en_US.UTF-8";
      LC_IDENTIFICATION = lib.mkDefault "en_US.UTF-8";
      LC_MEASUREMENT = lib.mkDefault "en_US.UTF-8";
      LC_MONETARY = lib.mkDefault "en_US.UTF-8";
      LC_NAME = lib.mkDefault "en_US.UTF-8";
      LC_NUMERIC = lib.mkDefault "en_US.UTF-8";
      LC_PAPER = lib.mkDefault "en_US.UTF-8";
      LC_TELEPHONE = lib.mkDefault "en_US.UTF-8";
      LC_TIME = lib.mkDefault "en_US.UTF-8";
    };
  };
}
// {
  
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
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    # Linux-only system utilities
    pciutils
    usbutils
  ];
  
  # =============================================================================
  # COMMON PROGRAMS
  # =============================================================================
  
  programs = {
    # Enable zsh globally
    zsh.enable = true;
    
    # Enable git
    git.enable = true;
  };
}
// lib.optionalAttrs pkgs.stdenv.isLinux {
  # =============================================================================
  # SECURITY (NixOS only)
  # =============================================================================
  
  # Enable sudo (macOS has sudo by default)
  security.sudo.enable = lib.mkDefault true;
}

