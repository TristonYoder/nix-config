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
  modules.services.infrastructure.tailscale.loginServer = lib.mkDefault "https://${config.modules.services.infrastructure.headscale.domain}";
  
  # Technitium DNS Server for edge DNS resolution
  modules.services.infrastructure.technitium.enable = lib.mkDefault true;

  # Headscale coordination server (self-hosted Tailscale control plane)
  modules.services.infrastructure.headscale = {
    enable = lib.mkDefault true;
    # Use vpn.<baseDomain> as base_domain for MagicDNS
    # This makes devices accessible as hostname.vpn.<baseDomain>
    baseDomain = lib.mkDefault "vpn.${config.networking.domain}";
    # Headscale control server at ts.<baseDomain>
    domain = lib.mkDefault "ts.${config.networking.domain}";

    # API key from agenix
    apiKeyFile = lib.mkDefault config.age.secrets.headscale-api-key.path;

    adminUI = {
      type = lib.mkDefault "admin";
    };

    oidc = {
      enable = lib.mkDefault true;
      issuer = lib.mkDefault "https://id.${config.networking.domain}";
      clientId = lib.mkDefault "fab17c4a-661a-4e5a-b6e0-eddcb9d9e06e";
      clientSecretFile = lib.mkDefault config.age.secrets.headscale-oidc-secret.path;
      allowedGroups = lib.mkDefault [ "vpn_user" ];
      pkce = {
        enabled = lib.mkDefault true;
        method = lib.mkDefault "S256";
      };
    };
  };

  # Cloudflare tunnel is only on david (server profile), not on edge servers
  # Cloudflared disabled - only run on main server
  modules.services.infrastructure.cloudflared.enable = lib.mkDefault false;
  
  # =============================================================================
  # DEVELOPMENT SERVICES
  # =============================================================================
  
  # Minimal development tools for remote management
  modules.services.development.vscode-server.enable = lib.mkDefault true;
  
  # GitHub Actions for automated deployment
  modules.services.development.github-actions.enable = lib.mkDefault true;
  
  # =============================================================================
  # COMMUNICATION SERVICES
  # =============================================================================
  
  # Well-known delegation for federation (Matrix, Pixelfed, etc.)
  modules.services.communication.wellknown.enable = lib.mkDefault true;
  
  # Postal Mail Server (SMTP relay on edge servers with public IP)
  modules.services.communication.postal.enable = lib.mkDefault true;
  
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

  # =============================================================================
  # DNS CONFIGURATION
  # =============================================================================
  
  # Configure DNS servers to use Cloudflare DNS
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
}
