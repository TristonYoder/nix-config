{ config, lib, pkgs, nixpkgs, nixpkgs-unstable, ... }:

let
  # Use unstable packages for some services that need newer versions
  unstable = nixpkgs-unstable.legacyPackages.${pkgs.system};
  
  # Cloudflare API Token - should be moved to secrets management
  cloudflareApiToken = "mDB6U0PcLl-QtjAlX5gskVgH4UO7_QMo5eLY0POq";
  
  # Helper function to create a virtual host with reverse proxy and TLS
  createVirtualHost = target: ''
    reverse_proxy ${target}
    ${sharedTlsConfig}
  '';
  
  # Shared TLS configuration for custom virtual hosts
  sharedTlsConfig = ''
    tls {
      dns cloudflare {
        api_token "${cloudflareApiToken}"
      }
    }
  '';
in
{
  # =============================================================================
  # SERVICES - ALPHABETICALLY ORGANIZED
  # =============================================================================

  # Actual Budget
  services.actual = {
    enable = true;
    settings.port = 1111;
    settings.hostname = "0.0.0.0";
    openFirewall = true;
  };

  services.caddy.virtualHosts."budget.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:1111";
  };

  # Audiobookshelf (commented out - using Docker version)
  # services.audiobookshelf = {
  #   enable = true;
  #   port = 13378;
  # };

  services.caddy.virtualHosts."audiobooks.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:13378";
  };

  # Audiobooksync
  services.caddy.virtualHosts."audiobooksync.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:13379";
  };

  # Caddy with Cloudflare DNS plugin
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = "sha256-p9AIi6MSWm0umUB83HPQoU8SyPkX5pMx989zAi8d/74=";
    };
    globalConfig = ''
      email triston@7andco.studio
    '';

    # Global options block for the Caddyfile
    extraConfig = ''
      # Global configuration can go here
    '';
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Cloudflare Tunnel Configuration
  users.users.cloudflared = {
    group = "cloudflared";
    isSystemUser = true;
  };
  users.groups.cloudflared = { };

  systemd.services.cloudflared_tunnel = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token=eyJhIjoiNmU3MmU4ZTBhMzhjMWFlYWY1MjkzYWUzMDdiYTBjYWMiLCJ0IjoiNmM4YWVmY2YtZGQwZC00MTBhLWE3ZGMtYWEzMGMwZWQ4YzVjIiwicyI6Ik5EYzBaalE0TVRrdE9UazJNUzAwWkdRekxXRXhPRGN0WkRNME9EazNPRFppT0dZNCJ9";
      Restart = "always";
      User = "cloudflared";
      Group = "cloudflared";
    };
  };

  # Immich - Photo management
  services.immich = {
    enable = true;
    port = 2283;
    openFirewall = true;
    host = "0.0.0.0";
    mediaLocation = "/data/docker-appdata/immich/media";
    settings.server.externalDomain = "https://photos.theyoder.family";
  };

  services.caddy.virtualHosts."photos.theyoder.family" = {
    extraConfig = ''
      handle_path /share* {
        reverse_proxy http://localhost:2284
      }
      handle {
        reverse_proxy http://localhost:2283
      }
      ${sharedTlsConfig}
    '';
  };

  # Immich Public Proxy
  services.immich-public-proxy = {
    enable = true;
    immichUrl = "http://localhost:2283/";
    openFirewall = true;
    port = 2284;
  };

  services.caddy.virtualHosts."share.photos.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:2284";
  };

  # Jellyfin - Media server
  services.jellyfin = {
    enable = true;
    openFirewall = true;
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
  systemd.services.jellyfin.serviceConfig = {
    DeviceAllow = [ "char-drm rw" "char-nvidia-frontend rw" "char-nvidia-uvm rw" ];
    PrivateDevices = lib.mkForce false;
  };

  services.caddy.virtualHosts."media.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:8096";
  };

  # Jellyseerr - Media requests
  services.jellyseerr = {
    enable = true;
    openFirewall = true;
    port = 5055;
  };

  services.caddy.virtualHosts."request.theyoder.family requests.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:5055";
  };

  # n8n - Workflow automation
  services.n8n = {
    enable = true;
    openFirewall = true;
    webhookUrl = "n8n.7andco.dev";
    settings = {
      # Additional n8n settings can go here
    };
  };

  services.caddy.virtualHosts."n8n.7andco.dev" = {
    extraConfig = createVirtualHost "http://localhost:5678";
  };

  # Nextcloud - File sharing and collaboration
  services.caddy.virtualHosts."nextcloud.theyoder.family" = {
    extraConfig = ''
      tls internal

      root * /var/lib/nextcloud/data
      php_fastcgi unix//run/phpfpm/nextcloud.sock
      file_server

      log {
        output file /var/log/caddy/nextcloud-access.log {
          roll_size 5MB
          roll_keep 3
        }
      }

      @forbidden {
        path /.htaccess /config/* /data/* /db_structure/* /lib/* /templates/* /3rdparty/* /README
      }
      respond @forbidden 403

      redir /.well-known/carddav /remote.php/dav 301
      redir /.well-known/caldav /remote.php/dav 301

      header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
      encode gzip
    '';
  };

  # NextDNS Dynamic DNS
  systemd.services = {
    nextdns-dyndns = {
      path = [ pkgs.curl ];
      script = "curl https://link-ip.nextdns.io/{a_secret_was_here}/{a_secret_was_here}";
      startAt = "hourly";
    };
  };

  # PostgreSQL database
  services.postgresql = {
    enable = true;
    dataDir = "/data/docker-appdata/postgres";
    enableTCPIP = true;
  };

  # Steam gaming platform
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };
  
  # Sunshine - Game streaming
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;  
  };

  # Tailscale - VPN and networking
  services.tailscale.enable = true;
  services.tailscale.useRoutingFeatures = "both";
  services.tailscale.extraUpFlags = [
    "--ssh"
    "--advertise-routes=10.150.0.0/16"
    "--advertise-exit-node"
    "--snat-subnet-routes=false"
    "--accept-routes=false"
  ];

  # Workaround for Tailscale Wireguard Bug
  # https://github.com/NixOS/nixpkgs/issues/180175
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # Allow Tailscale to act as Router
  # Kernel-level IP forwarding for the host
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Technitium DNS Server
  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;
  };

  # Vaultwarden - Password manager
  services.vaultwarden = {
    enable = true;
    backupDir = "/data/docker-appdata/vaultwarden/backups";
    # https://github.com/dani-garcia/vaultwarden/blob/1.33.2/.env.template
    config = {
      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = 8222;
      DOMAIN = "https://vault.theyoder.family";
      ENABLE_WEBSOCKET = "true";
      SIGNUPS_ALLOWED = "false";
      SIGNUPS_VERIFY = "false";
      SENDS_ALLOWED = "true";
      INVITATIONS_ALLOWED = "true";
      INVITATION_ORG_NAME = "7 & Co. Vaultwarden";
      ADMIN_TOKEN = "supersecretadmintoken";
      SIGNUPS_DOMAINS_WHITELIST="7andco.studio, elizabehthallen.photography, theyoder.family";
    };
  };

  services.caddy.virtualHosts."vault.theyoder.family" = {
    extraConfig = createVirtualHost "http://localhost:8222";
  };

  # VSCode Server - Remote development
  services.vscode-server.enable = true;

  # =============================================================================
  # COMMENTED OUT SERVICES - Available for future use
  # =============================================================================

  # # Mastodon - Social media
  # services.mastodon = {
  #   enable = true;
  #   localDomain = "social.theyoder.family";
  #   webPort = 55001;
  #   streamingProcesses = 2;    
  # };

  # # Mattermost - Team communication
  # services.mattermost = {
  #   enable = true;
  #   dataDir = "/data/docker-appdata/mattermost/state";
  #   host = "0.0.0.0";
  #   port = 8065;
  #   siteName = "chat.theyoder.family";
  #   siteUrl = "https://chat.theyoder.family";
  #   database.peerAuth = true;
  # };

  # # Matrix - Decentralized communication
  # services.matrix-synapse = {
  #   enable = true;
  #   settings.server_name = "theyoder.family";
  #   settings.public_baseurl = "https://matrix.theyoder.family";
  #   settings.media_store_path = "/data/docker-appdata/matrix-synapse";
  #   # Additional matrix configuration...
  # };

  # # Kasm - Browser-based desktops
  # services.kasmweb = {
  #   enable = true;
  #   listenPort = 8775;
  #   datastorePath = "/data/docker-appdata/kasm/";
  #   networkSubnet = "172.29.0.0/16";
  # };

  # # Headscale - Self-hosted Tailscale control server
  # services.headscale = {
  #   enable = true;
  #   port = 4433;
  #   address = "0.0.0.0";
  # };

  # # Ollama - Local AI models
  # services.ollama = {
  #   enable = true;
  #   loadModels = [ "llama4:latest" "deepseek-r1:latest"];
  #   acceleration = "cuda";
  # };

  # # Open WebUI - AI interface
  # services.open-webui = {
  #   enable = true;
  #   port = 8182;
  #   host = "0.0.0.0";
  #   openFirewall = true;
  # };

  # # Pixelfed - Decentralized social media
  # services.pixelfed = {
  #   enable = true;
  #   dataDir = "/data/docker-appdata/pixelfed";
  #   domain = "pixel.theyoder.family";
  # };

  # # Plex - Media server
  # services.plex = {
  #   enable = true;
  #   openFirewall = true;
  # };

  # # Uptime Kuma - Monitoring
  # services.uptime-kuma = {
  #   enable = true;
  #   appriseSupport = true;
  #   settings = {
  #     PORT = "3002";
  #     HOST = "0.0.0.0";
  #     cloudflared-token = "{a_secret_was_here}";
  #   };
  # };
}
