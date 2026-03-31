{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.media.jellyfin;
in
{
  options.modules.services.media.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";
    
    domain = mkOption {
      type = types.str;
      default = "media.${config.networking.domain}";
      description = "Domain for Jellyfin";
    };
    
    port = mkOption {
      type = types.port;
      default = 8096;
      description = "Jellyfin port (reverse proxy target)";
    };

    mediaDir = mkOption {
      type = types.str;
      default = "/data/media";
      description = "Root media directory";
    };

    mediaSubDirs = mkOption {
      type = types.listOf types.str;
      default = [ "Movies" "TV" "DVR" "Music" "Books" "Audiobooks" "Downloads" "Podcasts" "Games" "youtube" "Unsorted" "Plex" ];
      description = "Subdirectories under mediaDir to create with correct permissions";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Jellyfin";
    };

    pluginRepositories = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption { type = types.str; };
          url = mkOption { type = types.str; };
          enabled = mkOption { type = types.bool; default = true; };
        };
      });
      default = [
        {
          name = "Jellyfin Stable";
          url = "https://repo.jellyfin.org/releases/plugin/manifest-stable.json";
          enabled = true;
        }
      ];
      description = "Plugin repository manifests to configure in Jellyfin";
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

    # Add Jellyfin user to required groups for media access and GPU
    users.users.jellyfin.extraGroups = [ "media" "video" "render" ];

    # Add tristonyoder user to media group (for Docker containers)
    users.users.tristonyoder.extraGroups = [ "media" ];

    # Set proper permissions on media directory and subdirectories.
    # Mode 2775 sets setgid so new subdirectories inherit the media group automatically.
    systemd.tmpfiles.rules =
      [ "d ${cfg.mediaDir} 2775 tristonyoder media -" ]
      ++ map (sub: "d ${cfg.mediaDir}/${sub} 2775 tristonyoder media -") cfg.mediaSubDirs;

    # Write plugin repositories config on each Jellyfin start
    systemd.services.jellyfin.preStart =
      let
        reposXml = pkgs.writeText "jellyfin-repositories.xml" ''
          <?xml version="1.0" encoding="utf-8"?>
          <ArrayOfRepositoryInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            ${concatMapStrings (repo: ''
              <RepositoryInfo>
                <Name>${repo.name}</Name>
                <Url>${repo.url}</Url>
                <Enabled>${if repo.enabled then "true" else "false"}</Enabled>
              </RepositoryInfo>
            '') cfg.pluginRepositories}
          </ArrayOfRepositoryInfo>
        '';
        jellyfinConfigDir = config.services.jellyfin.configDir;
      in ''
        mkdir -p ${jellyfinConfigDir}
        install -m 644 ${reposXml} ${jellyfinConfigDir}/repositories.xml
      '';

    # Workaround for jellyfin hardware transcode (NVIDIA NVENC)
    # Minimal hardening overrides required for CUDA
    systemd.services.jellyfin.serviceConfig = mkIf cfg.enableHardwareTranscode {
      PrivateDevices = mkForce false;
      DevicePolicy = mkForce "closed";
      DeviceAllow = mkForce [
        # DRM/GPU render nodes
        "char-drm rw"
        # NVIDIA devices (major 195, 238-242)
        "/dev/nvidia0 rw"
        "/dev/nvidiactl rw"
        "/dev/nvidia-modeset rw"
        "/dev/nvidia-uvm rw"
        "/dev/nvidia-uvm-tools rw"
      ];
      NoNewPrivileges = mkForce false;
      SystemCallFilter = mkForce [ ];
      ProtectKernelModules = mkForce false;
      MemoryDenyWriteExecute = mkForce false;
      # Keep these enabled for security:
      # PrivateTmp, ProtectHome, ProtectSystem, ProtectKernelTunables,
      # ProtectKernelLogs, RestrictSUIDSGID, LockPersonality
    };

    # Add NVIDIA library path for CUDA/NVENC
    systemd.services.jellyfin.environment = mkIf cfg.enableHardwareTranscode {
      LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    };

    # Caddy virtual host
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
    };
  };
}
