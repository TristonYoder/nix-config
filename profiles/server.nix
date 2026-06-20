# Server Profile
# This profile is for the main server (david) that hosts all services

{ config, pkgs, lib, ... }:
{
  # =============================================================================
  # POWER MANAGEMENT — servers must never sleep or hibernate
  # =============================================================================

  # Disable all sleep/suspend/hibernate states at the systemd-sleep level
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernate = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # Ignore all power/lid events so logind never triggers a sleep
  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore";
    IdleAction = "ignore";
  };

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
  modules.system.users.useDataDrive = lib.mkDefault true;  # Symlink /home to /data
  modules.system.desktop.enable = lib.mkDefault true;

  # =============================================================================
  # INFRASTRUCTURE SERVICES
  # =============================================================================
  
  modules.services.infrastructure.caddy.enable = lib.mkDefault true;
  modules.services.vHosts.technitium = {
    enable = lib.mkDefault true;
    url = lib.mkDefault "https://dns01.${config.networking.domain}";
  };
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
  modules.services.media.jellyfin = {
    enable = lib.mkDefault true;
    pluginRepositories = lib.mkDefault [
      {
        name = "Jellyfin Stable";
        url = "https://repo.jellyfin.org/releases/plugin/manifest-stable.json";
        enabled = true;
      }
      {
        name = "n00bcodr Plugins";
        url = "https://raw.githubusercontent.com/n00bcodr/jellyfin-plugins/main/10.11/manifest.json";
        enabled = true;
      }
      {
        name = "Streamyfin";
        url = "https://raw.githubusercontent.com/streamyfin/jellyfin-plugin-streamyfin/main/manifest.json";
        enabled = true;
      }
    ];
  };
  modules.services.media.plex.enable = lib.mkDefault true;
  modules.services.media.jellyseerr.enable = lib.mkDefault true;
  modules.services.media.sunshine.enable = lib.mkDefault true;

  # =============================================================================
  # PRODUCTIVITY SERVICES
  # =============================================================================

  modules.services.productivity.babybuddy.enable = lib.mkDefault true;
  modules.services.productivity.companion.enable = lib.mkDefault true;
  modules.services.productivity.vaultwarden.enable = lib.mkDefault true;
  modules.services.productivity.n8n.enable = lib.mkDefault true;
  modules.services.productivity.actual.enable = lib.mkDefault true;
  modules.services.productivity.outline.enable = lib.mkDefault true;
  modules.services.productivity.tandoor.enable = lib.mkDefault true;

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
  # GAMING SERVICES
  # =============================================================================

  modules.services.gaming.romm.enable = lib.mkDefault true;

  # =============================================================================
  # DEVELOPMENT SERVICES
  # =============================================================================

  modules.services.development.vscode-server.enable = lib.mkDefault true;
  modules.services.development.github-actions.enable = lib.mkDefault true;
  modules.services.development.kasm.enable = lib.mkDefault true;
  modules.services.development.code-server.enable = lib.mkDefault true;

  # =============================================================================
  # AI SERVICES
  # =============================================================================

  modules.services.ai.hermes-agent.enable = lib.mkDefault true;
  modules.services.ai.litellm.enable     = lib.mkDefault true;
  modules.services.ai.open-webui.enable  = lib.mkDefault true;
  modules.services.ai.qdrant.enable      = lib.mkDefault true;

  # =============================================================================
  # DNS CONFIGURATION
  # =============================================================================

  # Configure DNS servers to use Cloudflare DNS
  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
}
