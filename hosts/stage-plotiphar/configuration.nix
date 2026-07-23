# Configuration for stage-plotiphar - Raspberry Pi 5 (CM5 Lite) signage kiosk
# Displays the stage-plotifer app (https://plotiphar.com) fullscreen, one
# Chromium instance per connected HDMI output. See profiles/kiosk.nix for
# the shared kiosk role and modules/services/kiosk for the browser/reset logic.

{ config, pkgs, lib, ... }:
{
  networking.hostName = "stage-plotiphar";
  system.stateVersion = "25.05";

  # =============================================================================
  # HARDWARE OVERRIDES
  # =============================================================================

  # "kernel" is the new generational RPi5 bootloader (supports multiple NixOS
  # generations) and is what the nixos-raspberrypi installer images use by
  # default — recommended for new installs over the legacy "kernelboot".
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Pi 5 firmware/bootloader owns /boot/firmware — not systemd-boot/EFI.
  # (profiles/kiosk.nix defaults this on for kiosk hosts in general, e.g. the
  # Parallels test VM at hosts/stage-plotiphar-vm.)
  modules.hardware.boot.enable = lib.mkForce false;

  # Only one of the two micro-HDMI ports has a monitor attached today;
  # kiosk-launcher detects connected outputs at boot rather than assuming both.

  # Boot splash — branded for plotiphar.com rather than the generic theme
  # profiles/kiosk.nix defaults to. See pkgs/plymouth-plotiphar-theme.
  #
  # extraConfig is appended *inside* the [Daemon] section the NixOS module
  # already generates from `theme`/`showDelay` — it must not re-open
  # "[Daemon]" itself (that produced a duplicate-header plymouthd.conf,
  # harmless to the ini parser but confusing to read). Only DeviceTimeout
  # has no dedicated option, so that's all that belongs here.
  boot.plymouth = {
    theme = "plotiphar";
    themePackages = [ (pkgs.callPackage ../../pkgs/plymouth-plotiphar-theme { }) ];
    extraConfig = "DeviceTimeout=5";
  };

  # vc4 (the real KMS driver for the Pi 5's HDMI outputs) otherwise only
  # loads in stage 2, ~4s after Plymouth already started against the
  # generic simpledrm device from initrd — confirmed via `journalctl -b`:
  # "Initialized simpledrm ... minor 0" precedes "Show Plymouth Boot
  # Screen" by well under a second, while "Initialized vc4 ... minor 1"
  # and the per-connector HDMI bind messages don't finish until ~4s later,
  # during switch-root. Plymouth doesn't hand off from one DRM device to
  # another mid-boot, so it keeps drawing to simpledrm while vc4 takes over
  # the actual scanout — net effect, the splash never appears on screen.
  # Loading vc4 in the initrd itself avoids the handoff entirely.
  boot.initrd.availableKernelModules = [ "vc4" ];

  # btrfs recommends periodic scrubs to catch bitrot early; unlike
  # tristons-workstation this box has no admin routinely poking at it, so
  # automate it rather than relying on someone remembering.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };

  # =============================================================================
  # NETWORK
  # =============================================================================

  networking.useDHCP = lib.mkDefault true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # WiFi (TPCC_Production) — the venue has no permanent Ethernet drop. PSK is
  # agenix-encrypted (decrypted here at activation via this host's own SSH
  # host key) rather than the local-only/--impure pattern used for the
  # one-shot installer image: this is an ongoing host, and any future
  # `nixos-rebuild switch` — from another machine, CI, without --impure —
  # would otherwise silently drop the WiFi config and strand it.
  age.secrets.stage-plotiphar-wifi-psk = {
    file = ../../secrets/stage-plotiphar-wifi-psk.age;
    mode = "0400";
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.age.secrets.stage-plotiphar-wifi-psk.path ];
    profiles."TPCC_Production" = {
      connection = {
        id = "TPCC_Production";
        type = "wifi";
      };
      wifi = {
        mode = "infrastructure";
        ssid = "TPCC_Production";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        # Substituted from the agenix-decrypted environmentFile at activation
        # (envsubst) — never appears in the Nix store.
        psk = "$WIFI_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
