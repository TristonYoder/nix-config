{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.jellyfin;
  
  # Caddy virtual host configuration with Cloudflare DNS TLS
  sharedTlsConfig = ''
    tls {
      dns cloudflare {$CLOUDFLARE_API_TOKEN}
    }
  '';
in
{
  options.modules.services.media.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";
    
    domain = mkOption {
      type = types.str;
      default = "media.theyoder.family";
      description = "Domain for Jellyfin";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Jellyfin";
    };
    
    enableHardwareTranscode = mkOption {
      type = types.bool;
      default = true;
      description = "Enable hardware transcoding with GPU";
    };
  };

  config = mkIf cfg.enable {
    # Jellyfin service
    services.jellyfin = {
      enable = true;
      openFirewall = cfg.openFirewall;
    };

    # Create media group for shared access to /data/media
    users.groups.media = { };

    # Add Jellyfin user to media group for write access
    users.users.jellyfin.extraGroups = [ "media" ];

    # Add tristonyoder user to media group (for Docker containers)
    users.users.tristonyoder.extraGroups = [ "media" ];

    # Set proper permissions on /data/media directory
    systemd.tmpfiles.rules = [
      "d /data/media 0775 tristonyoder media -"
    ];

    # Workaround for jellyfin hardware transcode
    systemd.services.jellyfin.serviceConfig = mkIf cfg.enableHardwareTranscode {
      DeviceAllow = [ "char-drm rw" "char-nvidia-frontend rw" "char-nvidia-uvm rw" ];
      PrivateDevices = mkForce false;
    };

    # Caddy virtual host
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:8096
        ${sharedTlsConfig}
      '';
    };
  };
}

