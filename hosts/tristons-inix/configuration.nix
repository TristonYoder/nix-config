# Configuration for tristons-iNix
# NixOS on a 2017 iMac (iMac18,x, pre-T2). Same setup as tristons-nixbook-pro
# minus the T2 pieces (kernel, suspend workaround, touch bar).

{ config, pkgs, lib, ... }:
{
  imports = [
    # Picks wl or brcmfmac by chip at boot; shared with the installer ISO.
    ../imac-installer/broadcom-auto.nix
  ];

  # ===========================================================================
  # SYSTEM IDENTIFICATION
  # ===========================================================================

  networking.hostName = "tristons-iNix";
  system.stateVersion = "26.05";

  # ===========================================================================
  # HARDWARE
  # ===========================================================================

  modules.hardware.boot.enable = true;

  # Storage: the Fusion Drive (1 TB HDD + 26 GB Apple NVMe) as one bcachefs
  # filesystem, tiered like Fusion. Writes and metadata land on the SSD, hot
  # data is promoted to it, and everything drains to the HDD in the
  # background (lz4 on write, recompressed to zstd there). One copy only: the
  # SSD holds metadata and not-yet-drained writes, so losing it loses the
  # filesystem. Chosen deliberately on a non-critical machine to try bcachefs.
  # It's out of tree since 6.17; the fsType pulls in the module built from
  # bcachefs-tools for this kernel. Formatted with:
  #   bcachefs format --fs_label=nixos --compression=lz4 \
  #     --background_compression=zstd --foreground_target=ssd \
  #     --promote_target=ssd --background_target=hdd --metadata_target=ssd \
  #     --label=ssd.nvme /dev/nvme0n1p2 --label=hdd.hdd /dev/sda1
  # /home and /nix are subvolumes (bcachefs subvolume create).

  # Command/Control swap for the Apple keyboard. The lid settings it also
  # carries are inert on an iMac.
  modules.hardware.appleLaptop.enable = true;

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

  # Desktop apps come from profiles/workstation.nix.
  environment.systemPackages = with pkgs; [
    nfs-utils
  ];

  home-manager.users.tristonyoder.modules.appShortcuts.enable = true;

  # ===========================================================================
  # DESKTOP
  # ===========================================================================

  home-manager.users.tristonyoder.modules.plasma.enable = true;

  # Passwordless guest account -> locked-down kiosk browser at apps.theyoder.family
  modules.system.guestKiosk.enable = true;

  # Unattended RustDesk, enrolled in CortenDesk (secrets encrypted to this host).
  modules.services.infrastructure.rustdeskAgent.enable = true;
}
