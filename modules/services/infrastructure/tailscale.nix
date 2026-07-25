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

    showLoginQr = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Render a scannable QR code of the tailscale login URL on the
        physical/virtual console (tty1) whenever the node needs
        interactive authentication — e.g. authKeyFile is unset, expired,
        or already consumed. Lets you complete login from a phone with
        console-only access (no SSH, no Tailscale yet). A no-op once the
        node is already logged in — the service just exits.
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

    systemd.services.tailscale-login-qr = mkIf cfg.showLoginQr {
      description = "Show a QR code on the console for interactive tailscale login, if needed";
      # getty@tty1 owns /dev/tty1 by default — without conflicting it out,
      # our TTYPath grab either fails to attach or gets silently stomped by
      # the login prompt redrawing, so the QR never actually appears.
      conflicts = [ "getty@tty1.service" ];
      after = [ "tailscaled.service" "getty@tty1.service" ] ++ optional (cfg.authKeyFile != null) "tailscaled-autoconnect.service";
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ config.services.tailscale.package pkgs.qrencode pkgs.jq ];
      serviceConfig = {
        Type = "simple";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        Restart = "on-failure";
        RestartSec = "5s";
        # Hand tty1 back to a normal login prompt once we're done with it
        # (success or failure), rather than leaving it dark.
        ExecStopPost = "-${pkgs.systemd}/bin/systemctl start getty@tty1.service";
      };
      script = ''
        # Give tailscaled-autoconnect (if configured) a head start to log
        # in via authKeyFile before falling back to interactive/QR login.
        sleep 10

        getState() { tailscale status --json --peers=false | jq -r '.BackendState'; }

        while true; do
          case "$(getState)" in
            Running)
              exit 0
              ;;
            NeedsLogin|NeedsMachineAuth|Stopped)
              echo "=== Tailscale needs authentication — scan this QR code or visit the URL below ==="
              tailscale up ${optionalString (cfg.loginServer != "") "--login-server=${cfg.loginServer}"} 2>&1 | while IFS= read -r line; do
                echo "$line"
                case "$line" in
                  https://*) echo "$line" | qrencode -t ANSIUTF8 ;;
                esac
              done
              ;;
          esac
          sleep 5
        done
      '';
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

