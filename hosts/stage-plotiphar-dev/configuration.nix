# Configuration for stage-plotiphar-dev - Raspberry Pi 5 Model B signage kiosk,
# a second parallel host for testing the stage-plotifer app alongside the real
# venue host (hosts/stage-plotiphar, a CM5 Lite). Same kiosk role and browser
# stack; see profiles/kiosk.nix for the shared bits and modules/services/kiosk
# for the browser/reset/CEC logic.
#
# Differences from stage-plotiphar: stock Pi 5 Model B (not CM5), wired
# Ethernet on the home LAN instead of the venue's TPCC_Production WiFi (no
# WiFi secret needed here), and no venue-specific device pairing yet.

{ config, pkgs, lib, ... }:
{
  networking.hostName = "stage-plotiphar-dev";
  system.stateVersion = "25.05";

  # =============================================================================
  # HARDWARE OVERRIDES
  # =============================================================================

  # Same generational RPi5 bootloader as stage-plotiphar.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Pi 5 firmware/bootloader owns /boot/firmware — not systemd-boot/EFI.
  modules.hardware.boot.enable = lib.mkForce false;

  # btrfs recommends periodic scrubs to catch bitrot early — same convention
  # as stage-plotiphar and tristons-workstation.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };

  # =============================================================================
  # NETWORK
  # =============================================================================

  # Wired Ethernet on the home LAN — no venue WiFi to join here.
  networking.useDHCP = lib.mkDefault true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # =============================================================================
  # DISPLAY POWER (PLOTIPHAR OUTPUT DEVICE)
  # =============================================================================

  # Same CEC output-device support as stage-plotiphar, so this box can also
  # exercise TV power/input control during testing. No secret to provision —
  # the display shows a pairing code on screen and approving it in the app
  # issues this host its own credential.
  modules.services.kiosk.cecBridge.enable = true;

  # =============================================================================
  # CEC REMOTE CONTROL
  # =============================================================================

  environment.systemPackages = with pkgs; [
    v4l-utils  # cec-ctl
    libcec     # cec-client
  ];

  # Allow the main user to control CEC devices (/dev/cec*) without sudo
  users.users.${config.modules.system.users.mainUser.name}.extraGroups = [ "video" ];
}
