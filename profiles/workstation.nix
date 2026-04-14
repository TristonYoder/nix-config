# Workstation Profile
# Shared desktop applications and development tools for all workstations
# Imported by server.nix and individual workstation hosts

{ config, pkgs, lib, nixpkgs-unstable, ... }:

{
  # Import the base desktop profile for KDE and core desktop functionality
  imports = [
    ./desktop.nix
  ];

  # Use rpi-imager from unstable to fix build issue
  nixpkgs.overlays = [
    (final: prev: {
      rpi-imager = nixpkgs-unstable.legacyPackages.${prev.system}.rpi-imager;
    })
  ];

  # =============================================================================
  # DESKTOP APPLICATIONS
  # =============================================================================
  
  environment.systemPackages = with pkgs; [
    # Web browsers
    firefox
    
    # Media players
    vlc
    
    # Development tools
    vscode
    
    # Security & Password Management
    _1password-gui
    bitwarden
    
    # Terminal
    kitty  # Modern terminal (iterm2 alternative)
    
    # 3D Printing & Hardware
    orca-slicer
    rpi-imager  # Raspberry Pi Imager
    
    # Crypto & Hardware Wallets
    trezor-suite
    
    # Communication
    element-desktop

    # Notes & Knowledge Management
    obsidian
  ];
  
  # =============================================================================
  # GAMING
  # =============================================================================

  modules.services.gaming = {
    enable = lib.mkDefault true;
    steam.steamRomManager = true;
  };
}
