# Configuration for tristons-workstation - NixOS Desktop

{ config, pkgs, lib, ... }:
{
  imports = [ ./rgb.nix ];
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
  # noauto: don't add to remote-fs.target — the automount unit below handles
  # triggering. Without noauto, NixOS would also start this mount at boot
  # via remote-fs.target, racing with tailscale before the route is up.
  fileSystems."/data" = {
    device = "10.150.100.30:/";
    fsType = "nfs";
    options = [
      "noauto"
      "hard"
      "timeo=50"
      "retrans=3"
      "nfsvers=4"
    ];
  };

  # Wait for david to be reachable before attempting the NFS mount.
  # Two-phase script:
  #   1. Wait up to 30s for a route to 10.150.100.30 to exist. network-online.target
  #      fires as soon as any interface (e.g. eno1) has an IP, but the route to
  #      10.150.100.30 lives on enp7s0 which may complete DHCP slightly later.
  #      `ip route get` fails immediately (no output) when there is no route,
  #      so this loop rate-limits retries with sleep 1.
  #   2. Ping david up to 10 times once the route exists.
  # Always exits 0 — a down david just means the mount will fail gracefully.
  systemd.services.nfs-david-reachable = {
    description = "Wait for david NFS server (10.150.100.30) to be reachable";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'for i in $(seq 1 30); do ${pkgs.iproute2}/bin/ip route get 10.150.100.30 >/dev/null 2>&1 && break; sleep 1; done; for i in $(seq 1 10); do ${pkgs.iputils}/bin/ping -c1 -W1 10.150.100.30 && exit 0; done; exit 0'";
    };
    after = [ "network-online.target" "sys-subsystem-net-devices-enp7s0.device" ];
    wants = [ "network-online.target" ];
  };

  # Automount unit: presents /data on first access and triggers data.mount.
  #
  # DefaultDependencies=false is required to break the boot ordering cycle.
  # With the default (true), systemd adds data.automount to local-fs.target.wants/
  # automatically. That creates a cycle: local-fs.target -> data.automount ->
  # nfs-david-reachable -> network-online.target -> ... -> local-fs.target.
  # systemd resolves it by deleting the automount job so /data never mounts.
  #
  # With DefaultDependencies=false, local-fs.target no longer depends on
  # data.automount, so we can safely add After=network-online.target here.
  # This prevents early-boot accesses (nix-daemon cache check, NixOS activation)
  # from triggering the mount before the network is up.
  #
  # Before/Conflicts=umount.target replace what DefaultDependencies would have
  # added for clean shutdown ordering.
  systemd.automounts = [{
    where = "/data";
    wantedBy = [ "remote-fs.target" ];
    unitConfig = {
      DefaultDependencies = false;
      After = "network-online.target";
      Wants = "network-online.target";
      Before = "umount.target remote-fs.target";
      Conflicts = "umount.target";
    };
  }];

  # Define data.mount explicitly so we can add After/Requires=nfs-david-reachable.
  # environment.etc drop-ins can't create nested subdirectories (etc-builder
  # limitation), so we define the full mount unit here instead.
  # DefaultDependencies=false: prevent auto-adding to remote-fs.target or
  # any other target — the automount unit is the only trigger for this mount.
  systemd.mounts = [
    {
      where = "/data";
      what = "10.150.100.30:/";
      type = "nfs";
      options = "hard,timeo=50,retrans=3,nfsvers=4";
      after = [ "nfs-david-reachable.service" ];
      requires = [ "nfs-david-reachable.service" ];
      unitConfig.DefaultDependencies = false;
    }

    # Host-local btrfs subvolumes mounted over ~/.local for each NFS-home user
    # so KDE Wallet and other app data stay on the local NVMe rather than NFS.
    {
      description = "Host-local ~/.local btrfs subvolume for tristonyoder";
      what = "/dev/disk/by-uuid/e2953d1f-2263-4331-9c3d-72dc1c7f000d";
      where = "/data/tristonyoder/home/.local";
      type = "btrfs";
      options = "subvol=@tristonyoder-local,compress=zstd,noatime,ssd,discard=async";
      after = [ "tristonyoder-dotlocal-mountpoint.service" ];
      requires = [ "tristonyoder-dotlocal-mountpoint.service" ];
      wantedBy = [ "graphical.target" ];
      unitConfig.DefaultDependencies = false;
    }

    {
      description = "Host-local ~/.local btrfs subvolume for carolineyoder";
      what = "/dev/disk/by-uuid/e2953d1f-2263-4331-9c3d-72dc1c7f000d";
      where = "/data/carolineyoder/home/.local";
      type = "btrfs";
      options = "subvol=@carolineyoder-local,compress=zstd,noatime,ssd,discard=async";
      after = [ "carolineyoder-dotlocal-mountpoint.service" ];
      requires = [ "carolineyoder-dotlocal-mountpoint.service" ];
      wantedBy = [ "graphical.target" ];
      unitConfig.DefaultDependencies = false;
    }
  ];

  # Ensure ~/.local mount points exist in NFS homes before mounting btrfs subvolumes
  # over them. /data may not have these directories pre-created on first boot.
  systemd.services.tristonyoder-dotlocal-mountpoint = {
    description = "Ensure tristonyoder ~/.local mount point exists in NFS home";
    after = [ "data.mount" ];
    requires = [ "data.mount" ];
    before = [ "data-tristonyoder-home-.local.mount" ];
    wantedBy = [ "data-tristonyoder-home-.local.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "tristonyoder";
      ExecStart = "${pkgs.coreutils}/bin/mkdir -p /data/tristonyoder/home/.local";
    };
  };

  systemd.services.carolineyoder-dotlocal-mountpoint = {
    description = "Ensure carolineyoder ~/.local mount point exists in NFS home";
    after = [ "data.mount" ];
    requires = [ "data.mount" ];
    before = [ "data-carolineyoder-home-.local.mount" ];
    wantedBy = [ "data-carolineyoder-home-.local.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "carolineyoder";
      ExecStart = "${pkgs.coreutils}/bin/mkdir -p /data/carolineyoder/home/.local";
    };
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
  # RDP SERVER
  # =============================================================================

  modules.system.krdp.enable = true;

  # =============================================================================
  # PACKAGES
  # =============================================================================

  services.hardware.openrgb = {
    enable = true;
    motherboard = "amd";
  };

  environment.systemPackages = with pkgs; [
    nfs-utils
    openrgb
    vlc
  ];
}
