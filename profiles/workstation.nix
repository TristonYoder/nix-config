# Workstation Profile
# Shared desktop applications and development tools for all workstations
# Imported by server.nix and individual workstation hosts

{ config, pkgs, lib, ... }:

{
  # Import the base desktop profile for KDE and core desktop functionality
  imports = [
    ./desktop.nix
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
    
    # Gaming
    steam
    
    # Communication
    element-desktop
  ];
  
  # =============================================================================
  # ADDITIONAL DEVELOPMENT SERVICES
  # =============================================================================
  
  # Inherit all development services from desktop.nix
  # Add workstation-specific development tools here if needed
}