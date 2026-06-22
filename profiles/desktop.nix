# Desktop Profile
# Minimal desktop configuration for workstations
# Includes core system, desktop environment, and development tools only

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # HARDWARE MODULES
  # =============================================================================
  
  modules.hardware.boot.enable = lib.mkDefault true;
  # NVIDIA is disabled by default, enable in host config if needed

  # =============================================================================
  # SYSTEM MODULES
  # =============================================================================
  
  modules.system.core.enable = lib.mkDefault true;
  modules.system.networking.enable = lib.mkDefault true;
  modules.system.users.enable = lib.mkDefault true;
  modules.system.desktop.enable = lib.mkDefault true;
  modules.system.auto-update.enable = lib.mkDefault true;

  # =============================================================================
  # DEVELOPMENT SERVICES (minimal set)
  # =============================================================================
  
  modules.services.development.vscode-server.enable = lib.mkDefault true;
  
  # =============================================================================
  # Tailscale for VPN access
  # =============================================================================
  
  modules.services.infrastructure.tailscale.enable = lib.mkDefault true;

  environment.systemPackages = [ pkgs.feishin pkgs.nmap ];

  # =============================================================================
  # BOOT SPLASH (desktop only - servers/edge are headless)
  # =============================================================================

  modules.hardware.displayResolution.enable = lib.mkDefault true;

  boot.plymouth = {
    enable = true;
    theme = "colorful";
    themePackages = with pkgs; [
      (adi1090x-plymouth-themes.override {
        selected_themes = [ "colorful" ];
      })
    ];
    extraConfig = ''
      [Daemon]
      Theme=colorful
      ShowDelay=0
      DeviceTimeout=5
    '';
  };

  boot.kernelParams = [ "splash" ];

  # All other services disabled by default
  # Individual desktops can enable specific services in their host config
}

