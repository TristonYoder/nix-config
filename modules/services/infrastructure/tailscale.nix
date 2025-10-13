{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.tailscale;
in
{
  options.modules.services.infrastructure.tailscale = {
    enable = mkEnableOption "Tailscale VPN";
    
    enableSSH = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tailscale SSH";
    };
    
    advertiseRoutes = mkOption {
      type = types.str;
      default = "10.150.0.0/16";
      description = "Subnets to advertise";
    };
    
    advertiseExitNode = mkOption {
      type = types.bool;
      default = true;
      description = "Advertise as exit node";
    };
    
    enableIPForwarding = mkOption {
      type = types.bool;
      default = true;
      description = "Enable kernel-level IP forwarding for routing";
    };
  };

  config = mkIf cfg.enable {
    # Tailscale service configuration
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "both";
      extraUpFlags = [
        (optionalString cfg.enableSSH "--ssh")
        "--advertise-routes=${cfg.advertiseRoutes}"
        (optionalString cfg.advertiseExitNode "--advertise-exit-node")
        "--snat-subnet-routes=false"
        "--accept-routes=false"
      ];
    };

    # Workaround for Tailscale Wireguard Bug
    # https://github.com/NixOS/nixpkgs/issues/180175
    systemd.services.NetworkManager-wait-online.enable = mkForce false;
    systemd.services.systemd-networkd-wait-online.enable = mkForce false;

    # Kernel-level IP forwarding for the host
    boot.kernel.sysctl = mkIf cfg.enableIPForwarding {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}

