# Configuration for tristons-nixbook-pro
# NixOS on 2019 T2 MacBook Pro 16,1 (dual boot alongside macOS)

{ config, pkgs, lib, ... }:
{
  # ===========================================================================
  # SYSTEM IDENTIFICATION
  # ===========================================================================

  networking.hostName = "tristons-nixbook-pro";
  system.stateVersion = "25.05";

  # ===========================================================================
  # HARDWARE
  # ===========================================================================

  # WiFi firmware fetched from macOS Sonoma installer via Asahi extraction scripts.
  # Fully reproducible — no manual firmware extraction from macOS required.
  hardware.apple-t2.firmware = {
    enable = true;
    version = "sonoma";
  };

  hardware.apple.touchBar.settings.MediaLayerDefault = true;

  # Intel UHD 630 VA-API support.
  hardware.graphics = {
    extraPackages = with pkgs; [ intel-media-driver ];
    extraPackages32 = with pkgs.pkgsi686Linux; [ intel-media-driver ];
  };

  # steamwebhelper (CEF) crashes on NixOS because pressure-vessel's ldconfig
  # can't detect host library architecture and fails to overlay the 32-bit Mesa
  # GBM driver into the container. Disabling browser HW acceleration in
  # steamwebhelper avoids the GPU init path that hits the CHECK(false) crash.
  # Games are unaffected — only Steam's own UI uses software rendering.
  environment.sessionVariables.STEAM_DISABLE_BROWSER_HARDWARE_ACCELERATION = "1";

  # systemd-boot on the shared EFI partition with macOS
  modules.hardware.boot.enable = true;

  # ===========================================================================
  # KEYBOARD — SWAP COMMAND AND CONTROL
  # ===========================================================================

  # Mac keyboard has Command next to spacebar. Swap at kernel level so it
  # works across Wayland, X11, and TTY.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        leftmeta = "leftcontrol";
        leftcontrol = "leftmeta";
        rightmeta = "rightcontrol";
        rightcontrol = "rightmeta";
      };
    };
  };

  # ===========================================================================
  # STORAGE & SYNC
  # ===========================================================================

  modules.services.storage.syncthing = {
    enable = true;
    dataDir = "/home/tristonyoder";
    configDir = "/home/tristonyoder/.config/syncthing";
  };

  # Check for pre-built closures on david's NFS share and prompt to update
  modules.system.auto-update.enable = true;

  # david's /data directory via NFS (automounted, soft mount so boot succeeds
  # when david is unreachable)
  fileSystems."/data" = {
    device = "david.theyoder.family:/data";
    fsType = "nfs";
    options = [
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=10"
      "soft"
      "timeo=50"
      "retrans=3"
    ];
  };

  # ===========================================================================
  # POWER MANAGEMENT
  # ===========================================================================

  modules.hardware.t2Suspend = {
    enable = true;
    mode = "workaround";
  };

  # ===========================================================================
  # PACKAGES
  # ===========================================================================

  environment.systemPackages = with pkgs; [
    firefox
    vlc
    vscode
    nfs-utils
  ];
}
