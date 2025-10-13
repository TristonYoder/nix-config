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
    
    # Automatic garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
  
  # Allow unfree packages globally
  nixpkgs.config.allowUnfree = true;
  
  # =============================================================================
  # LOCALE & TIME (can be overridden per-host)
  # =============================================================================
  
  time.timeZone = lib.mkDefault "America/New_York";
  
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
  
  # =============================================================================
  # COMMON PACKAGES
  # =============================================================================
  
  environment.systemPackages = with pkgs; [
    # Essential tools
    git
    vim
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
    
    # System utilities
    pciutils
    usbutils
  ];
  
  # =============================================================================
  # SECURITY
  # =============================================================================
  
  # Enable sudo
  security.sudo.enable = lib.mkDefault true;
  
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

