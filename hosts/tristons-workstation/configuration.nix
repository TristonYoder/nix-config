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
  # NETWORKING — pin enp7s0 (10.150.100.x) as the default route
  # =============================================================================

  # Dual-NIC host: enp7s0 carries 10.150.100.x (the fast fiber path to david),
  # eno1 carries 10.150.10.x. Both currently get DHCP-assigned route metrics
  # that happen to favor enp7s0 (100 vs 101), but that's incidental, not
  # declared -- a DHCP server change could silently flip default-route
  # priority. This module is desktop-profile-wide (NetworkManager), which
  # doesn't read the low-level networking.interfaces.* options, so pin the
  # metric the way NetworkManager actually respects: a real connection
  # profile file. environment.etc can't be used here -- NixOS's /etc entries
  # are symlinks into /nix/store, and NetworkManager's keyfile plugin refuses
  # to load symlinked connection files. systemd-tmpfiles' "C+" (force-copy)
  # writes a real regular file instead, re-applied on every boot.
  systemd.tmpfiles.rules =
    let
      mkConnection = { id, uuid, iface, metric }: pkgs.writeText "${id}.nmconnection" ''
        [connection]
        id=${id}
        uuid=${uuid}
        type=ethernet
        interface-name=${iface}

        [ipv4]
        method=auto
        route-metric=${toString metric}

        [ipv6]
        method=auto
        addr-gen-mode=default
      '';
      enp7s0Conn = mkConnection {
        id = "enp7s0-primary";
        uuid = "8f3a1e2c-1b4d-4f6a-9c8e-1a2b3c4d5e6f";
        iface = "enp7s0";
        metric = 100;
      };
      eno1Conn = mkConnection {
        id = "eno1-secondary";
        uuid = "2b6c4d8e-3f5a-4b7c-9d1e-6f7a8b9c0d1e";
        iface = "eno1";
        metric = 200;
      };
    in
    [
      "C+ /etc/NetworkManager/system-connections/enp7s0-primary.nmconnection 0600 root root - ${enp7s0Conn}"
      "C+ /etc/NetworkManager/system-connections/eno1-secondary.nmconnection 0600 root root - ${eno1Conn}"
    ];

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
