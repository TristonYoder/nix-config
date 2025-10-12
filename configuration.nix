# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, lib, nixpkgs, nixpkgs-unstable, nix-bitcoin, ... }:
{
  # Note: Module imports are now handled by the flake.nix file
  # This allows for better modularity and flake-based dependency management

  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================
  
  networking.hostName = "david";
  networking.domain = "theyoder.family";
  system.stateVersion = "23.11"; # Did you read the comment?
  system.autoUpgrade.channel = "https://nixos.org/channels/nixos-23.11/";

  # =============================================================================
  # HARDWARE MODULES
  # =============================================================================
  
  modules.hardware.nvidia.enable = true;
  modules.hardware.boot.enable = true;

  # =============================================================================
  # SYSTEM MODULES
  # =============================================================================
  
  modules.system.core.enable = true;
  modules.system.networking.enable = true;
  modules.system.users.enable = true;
  modules.system.desktop.enable = true;

  # =============================================================================
  # INFRASTRUCTURE SERVICES
  # =============================================================================
  
  modules.services.infrastructure.caddy.enable = true;
  modules.services.infrastructure.cloudflared.enable = true;
  modules.services.infrastructure.postgresql.enable = true;
  modules.services.infrastructure.tailscale.enable = true;
  modules.services.infrastructure.technitium.enable = true;

  # =============================================================================
  # MEDIA SERVICES
  # =============================================================================
  
  modules.services.media.immich.enable = true;
  modules.services.media.jellyfin.enable = true;
  modules.services.media.jellyseerr.enable = true;
  modules.services.media.sunshine.enable = true;

  # =============================================================================
  # PRODUCTIVITY SERVICES
  # =============================================================================
  
  modules.services.productivity.vaultwarden.enable = true;
  modules.services.productivity.n8n.enable = true;
  modules.services.productivity.actual.enable = true;

  # =============================================================================
  # STORAGE SERVICES
  # =============================================================================
  
  modules.services.storage.zfs.enable = true;
  modules.services.storage.nfs.enable = true;
  modules.services.storage.samba.enable = true;
  modules.services.storage.syncthing.enable = true;

  # =============================================================================
  # DEVELOPMENT SERVICES
  # =============================================================================
  
  modules.services.development.vscode-server.enable = true;
  modules.services.development.github-actions.enable = true;

  # =============================================================================
  # ADDITIONAL SERVICES (from old apps.nix - to be migrated later)
  # =============================================================================
  
  # NextDNS Dynamic DNS
  systemd.services = {
    nextdns-dyndns = {
      path = [ pkgs.curl ];
      script = "curl https://link-ip.nextdns.io/{a_secret_was_here}/{a_secret_was_here}";
      startAt = "hourly";
    };
  };
  
  # Note: configuration.nix is now clean and declarative!
  # All service configuration details are in their respective modules.
  # To enable/disable a service, just toggle its enable flag above.
}
