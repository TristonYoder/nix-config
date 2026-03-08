# Configuration for tristons-nixbook - NixOS Laptop
# Desktop/workstation setup for laptop use

{ config, pkgs, lib, ... }:
{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "tristons-nixbook";
  system.stateVersion = "25.05";

  # =============================================================================
  # HOST-SPECIFIC SETTINGS
  # =============================================================================

  # All module enables are set in ../../profiles/desktop.nix
  # Override any profile settings here if needed for this specific host

  # Syncthing for bidirectional home directory sync with david
  modules.services.storage.syncthing = {
    enable = true;
    dataDir = "/home/tristonyoder";
    configDir = "/home/tristonyoder/.config/syncthing";
  };

  # =============================================================================
  # NIX BUILD OFFLOADING
  # =============================================================================

  # Use david's binary cache as a substituter
  modules.system.nix-cache-client = {
    enable = true;
    # Public key must be set after generating the signing keypair on david:
    # nix key generate-secret --key-name david-cache > /tmp/key
    # nix key convert-secret-to-public < /tmp/key
    publicKey = "david-cache:REPLACE_WITH_PUBLIC_KEY_AFTER_GENERATION";
  };

  # Offload builds to david via ssh-ng
  modules.system.remote-builder.enable = true;

  # =============================================================================
  # AUTO-UPDATE FROM DAVID
  # =============================================================================

  # Check for pre-built closures on david's NFS share and prompt to update
  modules.system.auto-update.enable = true;

  # =============================================================================
  # NFS MOUNTS
  # =============================================================================

  # Mount david's /data directory via NFS
  # Uses automount so it doesn't block boot if david is unreachable
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

  # =============================================================================
  # KEYBOARD LAYOUT - SWAP COMMAND AND CONTROL
  # =============================================================================

  # MacBook keyboard has Command (Super) next to spacebar where Ctrl
  # would be on a PC keyboard. Use keyd to swap at the kernel level
  # so it works in Wayland, X11, and TTY.
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

  # =============================================================================
  # ADDITIONAL PACKAGES FOR LAPTOP
  # =============================================================================

  environment.systemPackages = with pkgs; [
    # Desktop applications
    firefox
    vlc

    # Development tools
    vscode

    # NFS client support
    nfs-utils
  ];
}
