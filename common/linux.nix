# Common configuration for all Linux/NixOS hosts
# This file contains settings shared across all NixOS machines

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # NIX SETTINGS (NixOS specific)
  # =============================================================================
  
  nix.settings = {
    # Enable store optimization (safe on NixOS)
    auto-optimise-store = true;
  };
  
  # =============================================================================
  # LOCALE (NixOS specific)
  # =============================================================================
  
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
  # LINUX-SPECIFIC PACKAGES
  # =============================================================================
  
  environment.systemPackages = with pkgs; [
    # System utilities (Linux-only)
    pciutils
    usbutils
  ];
  
  # =============================================================================
  # PROGRAMS
  # =============================================================================
  
  programs = {
    # Enable git system-wide
    git.enable = true;
  };
  
  # =============================================================================
  # SECURITY
  # =============================================================================
  
  # Enable sudo
  security.sudo.enable = lib.mkDefault true;

  # =============================================================================
  # BOOT ASCII ART
  # =============================================================================

  # Purple ASCII art boot message for theyoder.family
  systemd.services.ascii-boot = {
    description = "ASCII Art Boot Message";
    wantedBy = [ "multi-user.target" ];
    before = [ "getty.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "show-ascii" ''
        # Purple color codes
        PURPLE='\033[0;35m'
        BRIGHT_PURPLE='\033[1;35m'
        MAGENTA='\033[0;95m'
        RESET='\033[0m'
        
        echo -e "
$BRIGHT_PURPLE████████ ██   ██ ███████ $PURPLE██    ██  ██████  ██████  ███████ ██████     $MAGENTA███████  █████  ███    ███ ██ ██      ██    ██ 
   ██    ██   ██ ██       $PURPLE██  ██  ██    ██ ██   ██ ██      ██   ██    $MAGENTA██      ██   ██ ████  ████ ██ ██       ██  ██  
   ██    ███████ █████    $PURPLE ████   ██    ██ ██   ██ █████   ██████     $MAGENTA█████   ███████ ██ ████ ██ ██ ██        ████   
   ██    ██   ██ ██       $PURPLE  ██    ██    ██ ██   ██ ██      ██   ██    $MAGENTA██      ██   ██ ██  ██  ██ ██ ██         ██    
   ██    ██   ██ ███████  $PURPLE  ██     ██████  ██████  ███████ ██   ██ ██ $MAGENTA██      ██   ██ ██      ██ ██ ███████    ██    $RESET
                                                                                                                                        
$PURPLE                            ╔════════════════════════════════╗
                            ║     FAMILY INFRASTRUCTURE     ║
                            ║        Powered by NixOS       ║
                            ║      Host: ${config.networking.hostName}                ║
                            ╚════════════════════════════════╝$RESET
        "
        
        # Brief pause to let users see the message
        sleep 2
      ''}";
    };
  };
}

