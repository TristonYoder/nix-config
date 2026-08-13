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

  # Boot splash: uses profiles/kiosk.nix's standard "colorful" theme, same as
  # every other kiosk host. A custom plotiphar-branded theme was tried and
  # reverted — Plymouth's DRM renderer binds to the generic `simpledrm`
  # device before the real `vc4` KMS driver is ready and never re-scans, so
  # the splash fell back to Plymouth's built-in text mode regardless of
  # theme. Fixing that properly would need a custom kernel build (simpledrm
  # is compiled in, not a blacklist-able module) — not worth it for a
  # cosmetic boot splash. See git history on this file / profiles/kiosk.nix
  # for what was tried.

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

  # =============================================================================
  # CEC REMOTE CONTROL
  # =============================================================================

  # Tools for CEC display power control (power on/off connected TVs via HDMI).
  # v4l-utils provides cec-ctl; libcec provides cec-client.
  environment.systemPackages = with pkgs; [
    v4l-utils  # cec-ctl
    libcec     # cec-client
  ];

  # Allow the main user to control CEC devices (/dev/cec*) without sudo
  users.users.${config.modules.system.users.mainUser.name}.extraGroups = [ "video" ];
}

