{ config, pkgs, lib, ... }:
{
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

  # Audiobookshelf
  # services.audiobookshelf = {
  #   enable = true;
  #   port = 13378;
  # };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

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

}
