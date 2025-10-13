# Server Profile
# This profile is for the main server (david) that hosts all services

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # HARDWARE MODULES
  # =============================================================================
  
  modules.hardware.nvidia.enable = lib.mkDefault true;
  modules.hardware.boot.enable = lib.mkDefault true;

  # =============================================================================
  # SYSTEM MODULES
  # =============================================================================
  
  modules.system.core.enable = lib.mkDefault true;
  modules.system.networking.enable = lib.mkDefault true;
  modules.system.users.enable = lib.mkDefault true;
  modules.system.desktop.enable = lib.mkDefault true;

  # =============================================================================
  # INFRASTRUCTURE SERVICES
  # =============================================================================
  
  modules.services.infrastructure.caddy.enable = lib.mkDefault true;
  modules.services.infrastructure.cloudflared.enable = lib.mkDefault true;
  modules.services.infrastructure.postgresql.enable = lib.mkDefault true;
  modules.services.infrastructure.tailscale.enable = lib.mkDefault true;
  modules.services.infrastructure.technitium.enable = lib.mkDefault true;

  # =============================================================================
  # MEDIA SERVICES
  # =============================================================================
  
  modules.services.media.immich.enable = lib.mkDefault true;
  modules.services.media.jellyfin.enable = lib.mkDefault true;
  modules.services.media.jellyseerr.enable = lib.mkDefault true;
  modules.services.media.sunshine.enable = lib.mkDefault true;

  # =============================================================================
  # PRODUCTIVITY SERVICES
  # =============================================================================
  
  modules.services.productivity.vaultwarden.enable = lib.mkDefault true;
  modules.services.productivity.n8n.enable = lib.mkDefault true;
  modules.services.productivity.actual.enable = lib.mkDefault true;

  # =============================================================================
  # STORAGE SERVICES
  # =============================================================================
  
  modules.services.storage.zfs.enable = lib.mkDefault true;
  modules.services.storage.nfs.enable = lib.mkDefault true;
  modules.services.storage.samba.enable = lib.mkDefault true;
  modules.services.storage.syncthing.enable = lib.mkDefault true;

  # =============================================================================
  # DEVELOPMENT SERVICES
  # =============================================================================
  
  modules.services.development.vscode-server.enable = lib.mkDefault true;
  modules.services.development.github-actions.enable = lib.mkDefault true;
}

