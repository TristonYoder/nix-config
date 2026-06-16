# Configuration for tristons-workstation - NixOS Desktop

{ config, pkgs, lib, ... }:
{
  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "tristons-workstation";
  system.stateVersion = "25.05";

  # Passwordless sudo CI/automation user (standard on all hosts)
  modules.services.development.github-actions.enable = true;

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
  # SWAP
  # =============================================================================

  # The live installer had no swap at all, which is what caused the OOM
  # during first install (building Steam + 11 emulators + DaVinci Resolve
  # in one closure). The installed system inherited that same swapless
  # state -- add real swap before re-enabling that full closure below.
  swapDevices = [
    { device = "/swapfile"; size = 16384; }
  ];

  # =============================================================================
  # GAMING — re-enabled now that the system has its own swap (see above)
  # =============================================================================

  # profiles/workstation.nix already defaults this to true; no override needed.

  # =============================================================================
  # PACKAGES
  # =============================================================================

  environment.systemPackages = with pkgs; [
    nfs-utils
    vlc
  ];
}
