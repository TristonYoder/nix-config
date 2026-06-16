# Configuration for tristons-workstation - NixOS Desktop

{ config, pkgs, lib, ... }:
{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "tristons-workstation";
  system.stateVersion = "25.05";

  # =============================================================================
  # HOME DIRECTORY ON DAVID VIA NFS
  # =============================================================================

  # Home lives on david's /data share — hard mount since fiber backhaul is reliable
  fileSystems."/data" = {
    device = "david.theyoder.family:/data";
    fsType = "nfs";
    options = [
      "hard"
      "timeo=50"
      "retrans=3"
      "nfsvers=4"
    ];
  };

  # Symlink /home/tristonyoder -> /data/tristonyoder/home
  modules.system.users.useDataDrive = true;

  # =============================================================================
  # HARDWARE
  # =============================================================================

  modules.hardware.nvidia = {
    enable = true;
    useOpenSource = true;  # RTX 4080 (Ada Lovelace) — open modules recommended
  };

  # =============================================================================
  # BTRFS
  # =============================================================================

  services.btrfs.autoScrub.enable = true;

  # =============================================================================
  # PACKAGES
  # =============================================================================

  environment.systemPackages = with pkgs; [
    nfs-utils
    vlc
  ];
}
