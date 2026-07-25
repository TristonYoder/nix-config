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

    loginServer = mkOption {
      type = types.str;
      default = "https://ts.theyoder.family";
      description = "Headscale login server URL (empty uses default Tailscale coordination)";
    };

    authKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a decrypted preauth key (e.g. an agenix secret path). When
        set, forwarded to services.tailscale.authKeyFile, which makes
        NixOS run `tailscale up` automatically via tailscaled-autoconnect.service
        on every boot — needed for unattended hosts that can't run
        `tailscale up` interactively (e.g. a headless first boot).
        Generate with: sudo headscale preauthkeys create --user <user> --expiration <duration>
      '';
    };

    advertiseTags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "tag:infra-theyoder-family" ];
      description = ''
        Tags to self-advertise via --advertise-tags (requires the preauthkey's
        user to be a tagOwner of each tag in headscale's ACL policy). Only
        useful alongside authKeyFile — interactive `tailscale up` prompts for
        tag approval instead.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Tailscale service configuration
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "both";
      authKeyFile = cfg.authKeyFile;
      extraUpFlags = [
        (optionalString (cfg.loginServer != "") "--login-server=${cfg.loginServer}")
        (optionalString cfg.enableSSH "--ssh")
        (optionalString (cfg.advertiseRoutes != "") "--advertise-routes=${cfg.advertiseRoutes}")
        (optionalString cfg.advertiseExitNode "--advertise-exit-node")
        (optionalString (cfg.advertiseTags != [ ]) "--advertise-tags=${concatStringsSep "," cfg.advertiseTags}")
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

