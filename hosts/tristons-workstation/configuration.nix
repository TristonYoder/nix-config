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

  # Home lives on david's /data share — hard mount since fiber backhaul is reliable.
  #
  # Static IP, not the DNS hostname: at boot, DNS for *.theyoder.family only
  # resolves once Tailscale is up, but Tailscale itself isn't needed for this
  # mount (both hosts share the same 10.150.100.0/23 LAN segment) — using the
  # hostname made this mount silently depend on Tailscale auth for no reason.
  #
  # Path is "/" not "/data": david's NFS server marks /data as fsid=0, which
  # makes it the NFSv4 pseudo-root. NFSv4 clients address the pseudo-root as
  # "/", not the real on-disk path.
  fileSystems."/data" = {
    device = "10.150.100.30:/";
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
  # GAMING — disabled for initial install, re-enable post-install via rebuild
  # =============================================================================

  # workstation.nix profile defaults this on with every emulator enabled.
  # First install ran out of RAM building the full closure on a swapless
  # live installer — trim it here, add back selectively once the base
  # system is up and has its own swap.
  modules.services.gaming.enable = false;

  # =============================================================================
  # PACKAGES
  # =============================================================================

  environment.systemPackages = with pkgs; [
    nfs-utils
    vlc
  ];
}
