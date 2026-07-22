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

  # Only one of the two micro-HDMI ports has a monitor attached today;
  # kiosk-launcher detects connected outputs at boot rather than assuming both.

  # =============================================================================
  # NETWORK
  # =============================================================================

  networking.useDHCP = lib.mkDefault true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
