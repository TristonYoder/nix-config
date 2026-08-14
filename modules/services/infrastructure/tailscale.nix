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

    showLoginQr = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Render a scannable QR code of the tailscale login URL on the
        physical/virtual console (tty1) whenever the node needs
        interactive authentication — e.g. it has no preauth key yet, or
        an existing one expired. Lets you complete login from a phone
        with console-only access (no SSH, no Tailscale yet). A no-op
        once the node is already logged in — nothing touches tty1.

        Note: while the QR is up it owns /dev/tty1, so a display manager
        on the same host cannot start until login completes.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Tailscale service configuration
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "both";
      extraUpFlags = [
        (optionalString (cfg.loginServer != "") "--login-server=${cfg.loginServer}")
        (optionalString cfg.enableSSH "--ssh")
        "--advertise-routes=${cfg.advertiseRoutes}"
        (optionalString cfg.advertiseExitNode "--advertise-exit-node")
        "--snat-subnet-routes=false"
        "--accept-routes=false"
      ];
    };

    # Split in two on purpose. systemd opens TTYPath when the unit starts,
    # regardless of what the script does, and StandardInput=tty makes that
    # TTY the service's controlling terminal. A single always-started unit
    # therefore owned /dev/tty1 for as long as it polled, which made
    # sddm-helper's ioctl(TIOCSCTTY) on tty1 fail with EPERM and took
    # display-manager.service down with a start-limit-hit on every host with
    # a graphical greeter. So the polling half runs with no TTY at all, and
    # only starts the TTY-owning half when login is actually needed.
    systemd.services.tailscale-login-qr-watch = mkIf cfg.showLoginQr {
      description = "Watch for tailscale needing interactive login";
      after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ config.services.tailscale.package pkgs.jq ];
      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "5s";
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
              systemctl start --wait tailscale-login-qr.service || true
              ;;
          esac
          sleep 5
        done
      '';
    };

    systemd.services.tailscale-login-qr = mkIf cfg.showLoginQr {
      description = "Show a QR code on the console for interactive tailscale login";
      # Deliberately not wantedBy any target -- tailscale-login-qr-watch
      # starts it on demand. Anything that puts this in the boot transaction
      # takes /dev/tty1 away from the display manager.
      path = [ config.services.tailscale.package pkgs.qrencode ];
      serviceConfig = {
        Type = "simple";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
      };
      script = ''
        echo "=== Tailscale needs authentication — scan this QR code or visit the URL below ==="
        tailscale up ${optionalString (cfg.loginServer != "") "--login-server=${cfg.loginServer}"} 2>&1 | while IFS= read -r line; do
          echo "$line"
          case "$line" in
            https://*) echo "$line" | qrencode -t ANSIUTF8 ;;
          esac
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

