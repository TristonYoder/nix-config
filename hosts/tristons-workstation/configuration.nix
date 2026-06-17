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
      "x-systemd.automount"
      "hard"
      "timeo=50"
      "retrans=3"
      "nfsvers=4"
    ];
  };

  # Ping david for up to 10 seconds before attempting the NFS mount.
  # NFS routes through tailscale0, so the mount fails immediately if
  # Tailscale hasn't established its route yet. Always exits 0 so a
  # down david doesn't stall boot — the mount just fails gracefully.
  systemd.services.nfs-david-reachable = {
    description = "Wait for david NFS server (10.150.100.30) to be reachable";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 10); do ${pkgs.iputils}/bin/ping -c1 -W1 10.150.100.30 && exit 0; done; exit 0'";
    };
    after = [ "network.target" ];
    wantedBy = [ "data.mount" ];
    before = [ "data.mount" ];
  };

  # Symlink /home/tristonyoder -> /data/tristonyoder/home
  modules.system.users.useDataDrive = true;

  # Allow root to run nixos-rebuild from the NFS-backed repo.
  # Without this, libgit2 (used by nix) refuses to open a repo owned by
  # a different uid even when no_root_squash is set.
  programs.git.config.safe.directory = [ "/data/tristonyoder/home/Projects/nix-config" ];

  # =============================================================================
  # NETWORKING — pin enp7s0 (10.150.100.x) as the default route
  # =============================================================================

  # Dual-NIC host: enp7s0 carries 10.150.100.x (the fast fiber path to david,
  # named "Fiber (Core Services)" in NetworkManager), eno1 carries 10.150.10.x
  # ("Ethernet (User Devices)"). Both currently get DHCP-assigned route
  # metrics that happen to favor enp7s0 (100 vs 101), but that's incidental,
  # not declared -- a DHCP server change could silently flip default-route
  # priority. NetworkManager doesn't read the low-level networking.interfaces.*
  # options, so pin the metric the way it actually respects: in the existing
  # connection profile files themselves (matched by their real id/uuid below
  # -- a profile with a different uuid is just an inert duplicate, as
  # confirmed live: an earlier version of this used fresh enp7s0-primary/
  # eno1-secondary profiles and NetworkManager ignored them, since these two
  # pre-existing manually-created profiles were already bound to the devices).
  #
  # environment.etc can't be used here -- NixOS's /etc entries are symlinks
  # into /nix/store, and NetworkManager's keyfile plugin refuses to load
  # symlinked connection files. systemd-tmpfiles' "C" type only copies when
  # the target is *missing* -- confirmed live that "+" does NOT make it force
  # an overwrite of an existing file the way "f+"/"F+" do for other types, so
  # since these profiles already existed, C+ silently did nothing on every
  # rebuild. An activation script always runs and always copies, so use that
  # instead.
  system.activationScripts.pinNetworkManagerRouteMetrics =
    let
      fiberConn = pkgs.writeText "fiber.nmconnection" ''
        [connection]
        id=Fiber (Core Services)
        uuid=08f82423-5331-372b-b85e-365c56669f4b
        type=ethernet

        [ethernet]

        [ipv4]
        method=auto
        route-metric=100

        [ipv6]
        addr-gen-mode=stable-privacy
        method=auto

        [proxy]
      '';
      eno1Conn = pkgs.writeText "ethernet-user-devices.nmconnection" ''
        [connection]
        id=Ethernet (User Devices)
        uuid=4da1406d-7dc8-3cc4-8cef-6eaf6eab0ba5
        type=ethernet
        autoconnect-priority=-100

        [ethernet]

        [ipv4]
        method=auto
        route-metric=200

        [ipv6]
        addr-gen-mode=stable-privacy
        method=auto

        [proxy]
      '';
    in
    ''
      install -m 600 -o root -g root ${fiberConn} "/etc/NetworkManager/system-connections/Fiber.nmconnection"
      install -m 600 -o root -g root ${eno1Conn} "/etc/NetworkManager/system-connections/Ethernet (User Devices).nmconnection"
    '';

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

  # /data is NFS-mounted from david, so hit the cache directly on disk rather
  # than going through the HTTPS endpoint.
  modules.system.nixCache = {
    enable = true;
    cacheUrl = "file:///data/nix-builds/cache";
  };

  # =============================================================================
  # PACKAGES
  # =============================================================================

  environment.systemPackages = with pkgs; [
    nfs-utils
    vlc
  ];
}
