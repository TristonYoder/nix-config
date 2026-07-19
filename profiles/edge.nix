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
  # Default mainUser.packages (firefox, bitwarden-desktop, vscode, 1password-gui, ...) are
  # desktop GUI apps with no purpose on a headless edge box. CLI tools go in the host's
  # environment.systemPackages instead.
  modules.system.users.mainUser.packages = lib.mkDefault [ ];
  # Desktop disabled for headless edge servers
  modules.system.desktop.enable = lib.mkDefault false;

  # =============================================================================
  # INFRASTRUCTURE SERVICES (Minimal for Edge)
  # =============================================================================
  
  # Caddy for reverse proxy and public-facing services
  modules.services.infrastructure.caddy.enable = lib.mkDefault true;
  modules.services.providers.dns-technitium = {
    enable = lib.mkDefault true;
    url = lib.mkDefault "https://dns01.${config.networking.domain}";
  };
  
  # Tailscale for secure networking back to main infrastructure
  modules.services.infrastructure.tailscale.enable = lib.mkDefault true;
  
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
  
  # Postal Mail Server - NOT enabled by default in edge profile.
  # Enable explicitly in host config for hosts that need it (requires public IP for port 25).
  # modules.services.communication.postal.enable = lib.mkDefault true;
  
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
  
  # Daily GC for space-constrained VPS — overrides the monthly common default.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--max-old-count 3";
  };

  # Prune unused Docker images daily (keeps disk free on space-constrained VPS)
  virtualisation.docker.autoPrune = {
    enable = lib.mkDefault true;
    dates = lib.mkDefault "daily";
    flags = lib.mkDefault [ "--all" ];  # includes unused images, not just dangling
  };

  # Auto-trigger GC when free space drops below 5GB; free up to 10GB at a time
  nix.settings.min-free = lib.mkDefault (5 * 1024 * 1024 * 1024);
  nix.settings.max-free = lib.mkDefault (10 * 1024 * 1024 * 1024);

  # Optimize nix store
  nix.settings.auto-optimise-store = lib.mkDefault true;

  # =============================================================================
  # DNS CONFIGURATION
  # =============================================================================
  
  # Configure DNS servers to use Cloudflare DNS
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
}
