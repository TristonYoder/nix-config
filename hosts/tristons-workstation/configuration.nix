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
  # SWAP
  # =============================================================================

  # The live installer had no swap at all, which is what caused the OOM
  # during first install (building Steam + 11 emulators + DaVinci Resolve
  # in one closure). The installed system inherited that same swapless
  # state -- add real swap before re-enabling that full closure below.
  #
  # Sized for hibernation (RAM is ~31GiB; swap must be >= RAM, sized up
  # with headroom rather than cut exactly to it).
  swapDevices = [
    { device = "/swapfile"; size = 40960; }
  ];

  # Hibernation support: this is a swapfile on btrfs, not a dedicated
  # partition, so the kernel also needs resume_offset -- the physical
  # extent location of the file. Computed once via:
  #   sudo btrfs inspect-internal map-swapfile -r /swapfile
  # Re-run that and update this value if the swapfile is ever recreated
  # (e.g. resized again) -- the offset is tied to that specific file's
  # on-disk layout, not the path.
  boot.resumeDevice = config.fileSystems."/".device;
  boot.kernelParams = [
    "resume=${config.fileSystems."/".device}"
    "resume_offset=5275821"
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
