# Edge Server Profile
# Minimal configuration for edge nodes with public IP
# Designed for lightweight devices (Raspberry Pi, etc.) serving as entry points

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # HARDWARE MODULES
  # =============================================================================
  
  modules.hardware.boot.enable = lib.mkDefault true;
  # NVIDIA disabled for edge devices

  # =============================================================================
  # SYSTEM MODULES
  # =============================================================================
  
  modules.system.core.enable = lib.mkDefault true;
  modules.system.networking.enable = lib.mkDefault true;
  modules.system.users.enable = lib.mkDefault true;
  # Desktop disabled for headless edge servers
  modules.system.desktop.enable = lib.mkDefault false;

  # =============================================================================
  # INFRASTRUCTURE SERVICES (Minimal for Edge)
  # =============================================================================
  
  # Caddy for reverse proxy and public-facing services
  modules.services.infrastructure.caddy.enable = lib.mkDefault true;
  
  # Tailscale for secure networking back to main infrastructure
  modules.services.infrastructure.tailscale.enable = lib.mkDefault true;
  
  # Optional: Cloudflared for Cloudflare tunnel
  # modules.services.infrastructure.cloudflared.enable = lib.mkDefault false;
  
  # =============================================================================
  # DEVELOPMENT SERVICES
  # =============================================================================
  
  # Minimal development tools for remote management
  modules.services.development.vscode-server.enable = lib.mkDefault true;
  
  # GitHub Actions for automated deployment
  modules.services.development.github-actions.enable = lib.mkDefault true;
  
  # =============================================================================
  # COMMUNICATION SERVICES (Federation Discovery)
  # =============================================================================
  
  # Well-known delegation for federation (Matrix, Pixelfed, etc.)
  modules.services.communication.wellknown.enable = lib.mkDefault true;
  
  # =============================================================================
  # STORAGE (Optional)
  # =============================================================================
  
  # Syncthing for edge data synchronization
  # modules.services.storage.syncthing.enable = lib.mkDefault false;
  
  # All other services disabled by default
  # Edge servers should be minimal and focused on their specific role
  
  # =============================================================================
  # EDGE-SPECIFIC OPTIMIZATIONS
  # =============================================================================
  
  # Optimize for low-resource environments
  # These can be overridden in host-specific config if needed
  
  # Reduce journal size for limited storage
  services.journald.extraConfig = lib.mkDefault ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
  '';
  
  # Enable automatic garbage collection more aggressively
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "daily";
    options = lib.mkDefault "--delete-older-than 7d";
  };
  
  # Optimize nix store
  nix.settings.auto-optimise-store = lib.mkDefault true;
}

