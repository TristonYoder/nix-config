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
  # Cloudflared for Cloudflare tunnel
  modules.services.infrastructure.cloudflared = {
    enable = lib.mkDefault true;
    tokenFile = lib.mkDefault config.age.secrets.cloudflared-token-current.path;
  };
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
  # COMMUNICATION SERVICES
  # =============================================================================
  
  modules.services.communication.matrix-synapse = {
    enable = lib.mkDefault true;
    enableRegistration = lib.mkDefault true; # Temporarily enable for bridge setup
    enableRegistrationWithoutVerification = lib.mkDefault true; # Allow registration without email verification
  };
  modules.services.communication.mautrix-groupme.enable = lib.mkDefault true;
  modules.services.communication.mautrix-imessage.enable = lib.mkDefault true;
  modules.services.communication.pixelfed.enable = lib.mkDefault true;
  modules.services.communication.wellknown.enable = lib.mkDefault true;
  modules.services.communication.stalwart-mail.enable = lib.mkDefault true;

  # =============================================================================
  # STORAGE SERVICES
  # =============================================================================
  
  modules.services.storage.zfs.enable = lib.mkDefault true;
  modules.services.storage.nfs.enable = lib.mkDefault true;
  modules.services.storage.samba.enable = lib.mkDefault true;
  modules.services.storage.syncthing.enable = lib.mkDefault true;
  
  # Nextcloud with all apps enabled
  # modules.services.storage.nextcloud = {
  #   enable = lib.mkDefault true;
    
  #   # Built-in apps
  #   enableNews = true;
  #   enableMail = true;
  #   enableTables = true;
  #   enableForms = true;
  #   enableContacts = true;
  #   enableCalendar = true;
  #   enableGroupfolders = true;
  #   enableExternal = true;
    
  #   # Custom apps
  #   enableElementApp = false;
  #   enableUserSaml = false;
  #   enableRichdocumentscode = false;
  #   enableIntegrationNotion = false;
  #   enableIntegrationGithub = false;
  #   enableOfficeonline = false;
  #   enableElectronicsignatures = false;
  #   enableLibresign = false;
  #   enableFilesReadmemd = false;
  # };

  # =============================================================================
  # DEVELOPMENT SERVICES
  # =============================================================================
  
  modules.services.development.vscode-server.enable = lib.mkDefault true;
  modules.services.development.github-actions.enable = lib.mkDefault true;
  modules.services.development.kasm.enable = lib.mkDefault true;

  # =============================================================================
  # DNS CONFIGURATION
  # =============================================================================
  
  # Configure DNS servers to use Cloudflare DNS
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
}

