{ self, config, lib, pkgs, ... }: 
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

#Workaround for jellyfin hardware transcode
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
#     datastorePath = "/data/docker-appdata/kasmweb/";
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
  
  # VSCode
  imports = [
    (fetchTarball "https://github.com/nix-community/nixos-vscode-server/tarball/master")
  ];
  services.vscode-server.enable = true;
}
