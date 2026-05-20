# Configuration for tristons-nixbook-t2
# NixOS on 2019 T2 MacBook Pro (dual boot alongside macOS)

{ config, pkgs, lib, ... }:
{
  # ===========================================================================
  # SYSTEM IDENTIFICATION
  # ===========================================================================

  networking.hostName = "tristons-nixbook-t2";
  system.stateVersion = "25.05";

  # ===========================================================================
  # HARDWARE
  # ===========================================================================

  # T2 supplemental config: binary cache, WiFi firmware, suspend workaround,
  # trackpad kernel param. nixos-hardware.nixosModules.apple-t2 (in flake.nix)
  # handles the patched kernel and apple-bce driver.
  modules.hardware.appleT2 = {
    enable = true;
    wifiFirmware = true;  # BCM4364-B2 (maui board), extracted from macOS 2026-05-20
  };

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
  # PACKAGES
  # ===========================================================================

  environment.systemPackages = with pkgs; [
    firefox
    vlc
    vscode
    nfs-utils
  ];
}
