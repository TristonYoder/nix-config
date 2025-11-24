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
  # BOOT ASCII ART HEADER
  # =============================================================================

  # Display ASCII art header at boot and configure console for persistent display
  boot.kernelParams = [
    # Increase console buffer to accommodate header + boot messages
    "fbcon=scrollback:128k"
  ];

  # Create the ASCII art header script
  environment.etc."boot-header.sh" = {
    text = ''
      #!/bin/bash
      # Purple color codes
      PURPLE='\033[0;35m'
      BRIGHT_PURPLE='\033[1;35m'
      MAGENTA='\033[0;95m'
      RESET='\033[0m'
      
      # Display ASCII header
      echo -e "$BRIGHT_PURPLE████████ ██   ██ ███████ $PURPLE██    ██  ██████  ██████  ███████ ██████     $MAGENTA███████  █████  ███    ███ ██ ██      ██    ██$RESET"
      echo -e "$BRIGHT_PURPLE   ██    ██   ██ ██       $PURPLE██  ██  ██    ██ ██   ██ ██      ██   ██    $MAGENTA██      ██   ██ ████  ████ ██ ██       ██  ██$RESET"
      echo -e "$BRIGHT_PURPLE   ██    ███████ █████    $PURPLE ████   ██    ██ ██   ██ █████   ██████     $MAGENTA█████   ███████ ██ ████ ██ ██ ██        ████$RESET"
      echo -e "$BRIGHT_PURPLE   ██    ██   ██ ██       $PURPLE  ██    ██    ██ ██   ██ ██      ██   ██    $MAGENTA██      ██   ██ ██  ██  ██ ██ ██         ██$RESET"
      echo -e "$BRIGHT_PURPLE   ██    ██   ██ ███████  $PURPLE  ██     ██████  ██████  ███████ ██   ██ ██ $MAGENTA██      ██   ██ ██      ██ ██ ███████    ██$RESET"
      echo ""
      echo -e "$PURPLE                            ╔════════════════════════════════╗$RESET"
      echo -e "$PURPLE                            ║     FAMILY INFRASTRUCTURE     ║$RESET"
      echo -e "$PURPLE                            ║        Powered by NixOS       ║$RESET"
      echo -e "$PURPLE                            ║      Host: $(hostname)                ║$RESET"
      echo -e "$PURPLE                            ╚════════════════════════════════╝$RESET"
      echo ""
      echo -e "${PURPLE}Boot Messages:${RESET}"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    '';
    mode = "0755";
  };

  # Early boot service to display header
  systemd.services.boot-header = {
    description = "Boot ASCII Header";
    wantedBy = [ "sysinit.target" ];
    after = [ "systemd-journald.service" ];
    before = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/boot-header.sh";
      StandardOutput = "kmsg+console";
      StandardError = "kmsg+console";
    };
  };
}

