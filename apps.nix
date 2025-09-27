{ self, config, lib, pkgs, ... }: 
let
  # Cloudflare API Token as an environment variable
  cloudflareApiToken = "mDB6U0PcLl-QtjAlX5gskVgH4UO7_QMo5eLY0POq";
in
{
  # Actual Budget
  services.actual = {
    enable = true;
    settings.port = 1111;
    settings.hostname = "0.0.0.0";
    openFirewall = true;
  };

  # Audiobookshelf
  # services.audiobookshelf = {
  #   enable = true;
  #   port = 13378;
  # };

  # Caddy
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.1" ];
      hash = "sha256-AcWko5513hO8I0lvbCLqVbM1eWegAhoM0J0qXoWL/vI=";
    };
    globalConfig = ''
      email triston@7andco.studio
    '';

    # Global options block for the Caddyfile
    extraConfig = ''
      # Global configuration can go here
    '';

    virtualHosts = {
      "apps.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:7575
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "audiobooks.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:13378
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "audiobooksync.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:13379
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "btc.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:8997
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "budget.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:1111
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "carolineyoder.com" = {
        extraConfig = ''
          reverse_proxy http://localhost:1128
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "carolineelizabeth.photography elizabethallen.photography carolines.photos takemy.photo loveinfocus.photography" = {
        extraConfig = ''
          reverse_proxy http://localhost:1996
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "chat.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:8065
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "david.theyoder.family" = {
        extraConfig = ''
          respond "404" 404
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "home.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://10.150.2.117:8123
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "media.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:8096
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "mempool.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:8998
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "notes.theyoder.family notes.7andco.studio" = {
        extraConfig = ''
          reverse_proxy http://localhost:3010
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "nextcloud.theyoder.family" = {
        # This site-specific block overrides the global TLS settings
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

      "social.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:55001
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "photos.theyoder.family" = {
        extraConfig = ''
          handle_path /share* {
            reverse_proxy http://localhost:2284
          }
          handle {
            reverse_proxy http://localhost:2283
          }
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "share.photos.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:2284
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "poker.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:8234
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "request.theyoder.family requests.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:5055
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "recipies.theyoder.family food.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:6780
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "unifi.theyoder.family" = {
        extraConfig = ''
          reverse_proxy https://10.150.100.1 {
            transport http {
              tls
              tls_insecure_skip_verify
            }
          }
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };

      "vault.theyoder.family" = {
        extraConfig = ''
          reverse_proxy http://localhost:8222
          tls {
            dns cloudflare {
              api_token "${cloudflareApiToken}"
            }
          }
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Cloudflare Config
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

  # Jellyfin
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

     # Workaround for jellyfin hardware transcode
  systemd.services.jellyfin.serviceConfig = {
   # DeviceAllow = lib.mkForce [ "char-drm rw" ];
    DeviceAllow = [ "char-drm rw" "char-nvidia-frontend rw" "char-nvidia-uvm rw" ];
    PrivateDevices = lib.mkForce false;
  };

  services.jellyseerr = {
    enable = true;
    openFirewall = true;
    port = 5055;
  };

  # # Mastodon
  # services.mastodon = {
  #   enable = true;
  #   localDomain = "social.theyoder.family";
  #   webPort = 55001;
  #   streamingProcesses = 2;    
  # };

#  # cMatermost
#  services.mattermost = {
#    enable = true;
#    dataDir = "/data/docker-appdata/mattermost/state";
#    host = "0.0.0.0";
#    port = 8065;
#    siteName = "chat.theyoder.family";
#    siteUrl = "https://chat.theyoder.family";
#    database.peerAuth = true;
#  };

  # # Matrix
  # services.matrix-synapse = {
  #   enable = true;
  #   settings.server_name = "theyoder.family";
  #   settings.public_baseurl = "https://matrix.theyoder.family";
  #   settings.media_store_path = "/data/docker-appdata/matrix-synapse"
  #   settings.listeners = [
  #     {
  #       bind_addresses = [ "localhost" ];
	# port = 8448;
	# tls = false;
  #      resources = [
  #         { compress = true; names = ["client" "federation"]; }
	#   { compress = false; names = [ "federation" ]; }
  #       ];
	# type = "http";
	# x_forwarded = false;
  #     }
  #     {
	# bind_addresses = [ "127.0.0.1" ];
	# port = 8008;
	# resources = [ { compress = true; names = [ "client" "federation" ]; }
	# ];
	# tls = false;
	# type = "http";
	# x_forwarded = true;
  #     }
  #   ];
  # };

  # NextDNS Dynamic DNS
  systemd.services = {
    nextdns-dyndns = {
      path = [
        pkgs.curl
      ];
      script = "curl https://link-ip.nextdns.io/{a_secret_was_here}/{a_secret_was_here}";
      startAt = "hourly";
    };
  };

  # #Kasm
  #   services.kasmweb = {
  #     enable = true;
  #     listenPort = 8775;
  #     datastorePath = "/data/docker-appdata/kasm/";
  #     networkSubnet = "172.29.0.0/16";
  #   };

  # # Kasm Docker Network Setup
  #   systemd.services.docker-kasm_db_init = {
  #     description = "Initialize Kasm DB Container";

  #     # Define dependencies
  #     wants = [ "docker.service" ];
  #     after = [ "docker.service" ];

  #     # Explicitly override conflicting options
  #     serviceConfig = {
  #       Restart = lib.mkForce "on-failure";
  #       RestartSec = lib.mkForce "5s";
  #       ExecStartPre = lib.mkForce ''
  #         docker network inspect kasm_default_network >/dev/null 2>&1 || \
  #         docker network create kasm_default_network
  #       '';
  #       ExecStart = lib.mkForce ''
  #         docker run --rm --network kasm_default_network \
  #         --name kasm_db_init \
  #         kasm_base_image:latest db-init-command
  #       '';
  #     };
  #   };

  # # Headscale
  # services.headscale = {
  #   enable = true;
  #   port = 4433;
  #   address = "0.0.0.0";
  #  # settings.server_url = "https://vpn.theyoder.family:443";
  #  # settings.tls_key_path = "";
  #  # settings.tls_cert_path = "";
  # };

  # Immich
  services.immich = {
    enable = true;
    port = 2283;
    openFirewall = true;
    host = "0.0.0.0";
    mediaLocation = "/data/docker-appdata/immich/media";
    settings.server.externalDomain = "https://photos.theyoder.family";
  };

  # Immich Public Proxy
  services.immich-public-proxy = {
    enable = true;
    immichUrl = "http://localhost:2283/";
    openFirewall = true;
    port = 2284;
  };

  # n8n
  services.n8n = {
    enable = true;
    openFirewall = true;
    webhookUrl = "n8n.7andco.dev";
    
    #https://docs.n8n.io/hosting/environment-variables/configuration-methods/
    settings = {

    };
  };
  # # Ollama
  # services.ollama = {
  #   enable = true;
  #   # Optional: preload models, see https://ollama.com/library
  #   loadModels = [ "llama4:latest" "deepseek-r1:latest"];
  #   acceleration = "cuda";
  # };
  # nixpkgs.config.cudaSupport = true;
 
  # services.open-webui = {
  #   enable=true;
  #   port=8182;
  #   host="0.0.0.0";
  #   openFirewall=true;
  # };

  # Postgres
  services.postgresql = {
    enable = true;
    dataDir = "/data/docker-appdata/postgres";
    enableTCPIP = true;
  };

  # # Pixelfed
  # services.pixelfed = {
  #   enable = true;
  #   dataDir = "/data/docker-appdata/pixelfed";
  #   domain = "pixel.theyoder.family";
  # };

  # # Plex Config
  # services.plex = {
  #   enable = true;
  #   openFirewall = true;
  # };

  # Tailscale
  services.tailscale.enable = true;
  services.tailscale.useRoutingFeatures = "both";
  services.tailscale.extraUpFlags = [
    "--ssh"
    "--advertise-routes=10.150.0.0/16"
    "--advertise-exit-node"
    "--snat-subnet-routes=false"
    "--accept-routes=false"
  ];

  #Vaultwarden
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
  # Workaround for Wiregaurd Bug
  # https://github.com/NixOS/nixpkgs/issues/180175
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # Allow Tailscale to act as Router
  # Kernel-level IP forwarding for the host
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
   # protontricks.enable = true;
   # gamescopeSession.enable = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };
  
  # Sunshine
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;  
  };

  # Technitium DNS
  services.technitium-dns-server = {
    enable = true;
    openFirewall = true;
  };

  # # Uptime Kuma
  # services.uptime-kuma = {
  #   enable = true;
  #   appriseSupport = true;
  #   settings = {
  #     PORT = "3002";
  #     HOST = "0.0.0.0";
  #     cloudflared-token = "{a_secret_was_here}";
  #     };
  # };

  # VSCode
  imports = [
    (fetchTarball "https://github.com/nix-community/nixos-vscode-server/tarball/master")
  ];
  services.vscode-server.enable = true;

}
