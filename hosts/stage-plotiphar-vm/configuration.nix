# Configuration for stage-plotiphar-vm - Parallels test VM for the
# stage-plotiphar kiosk config. Same kiosk profile and browser-kiosk module
# as the real Pi 5, but boots as a standard UEFI live ISO instead of via the
# Pi 5's firmware boot chain, so it runs in Parallels (or any UEFI VM) on an
# Apple Silicon Mac. Disposable/ephemeral by design (live squashfs root) —
# not something you install to a disk or deploy to.
#
# What this DOES validate: X11/openbox/lightdm autologin coming up,
# kiosk-launcher launching Chromium in kiosk mode, the pairing flow, and the
# kiosk-url-tracker persistence logic.
#
# What this CANNOT validate (no equivalent in a VM): the pwr_button GPIO
# reset handler (kiosk-reset-button.service will just idle, never firing —
# there's no gpio-keys device to find), real dual-HDMI output detection
# (Parallels presents its own virtual display, not two physical HDMI ports),
# and anything Pi 5 firmware/fan/PoE-specific.

{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  networking.hostName = "stage-plotiphar-vm";
  system.stateVersion = "25.05";

  # Standard UEFI boot via systemd-boot/EFI (profiles/kiosk.nix default) would
  # conflict with the live-ISO's own bootloader setup — let the installer-cd
  # module own that instead.
  modules.hardware.boot.enable = lib.mkForce false;
  # common/linux.nix's boot.loader.timeout = 2 conflicts with iso-image.nix's
  # own default of 10 — same priority, so pick a winner explicitly.
  boot.loader.timeout = lib.mkForce 2;

  # installation-cd-base.nix defaults this true (hybrid MBR/GPT so the ISO
  # can also be dd'd to a USB stick). Our closure (X11 + Chromium + Python)
  # is much bigger than a normal minimal installer, and the hybrid layout's
  # size-estimation trips over that ("Image size ... exceeds free space on
  # media ..."). We only need this ISO to boot as a virtual CD in Parallels,
  # not from a USB stick, so just turn it off.
  isoImage.makeUsbBootable = lib.mkForce false;

  # Not needed for a disposable test VM; keeps the build lean and avoids
  # pulling in agenix/Tailscale-authkey requirements this throwaway host
  # doesn't have secrets for.
  modules.services.infrastructure.tailscale.enable = lib.mkForce false;
  modules.services.development.vscode-server.enable = lib.mkForce false;

  # installation-cd-minimal.nix already configures NetworkManager for easy
  # live-CD networking — leave it as-is rather than fighting it.

  # SSH is already enabled with PermitRootLogin=yes by the installer-device
  # profile; just need a key so it's reachable without console access. Lets
  # troubleshooting (restart services, reboot to get a fresh boot, read
  # journals) happen directly instead of relaying commands through the
  # console. No secret here — it's a public key, safe to commit.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz Triston Yoder"
  ];

  # browser-kiosk.nix's default stateDir (/var/lib/kiosk) couldn't be created
  # on the live ISO's root (read-only squashfs, no writable overlay for /var
  # in this profile). /run is tmpfs on every Linux system already — no new
  # mount needed — and it's actually the right behavior for a disposable
  # test VM anyway: every boot starts fresh, no stale cookies/URLs carried
  # over from a previous test run.
  modules.services.kiosk.browserKiosk.stateDir = "/run/kiosk";

  # Same branded boot splash as the real Pi (hosts/stage-plotiphar) — without
  # this override the VM just inherits profiles/kiosk.nix's generic default
  # theme, which defeats the point of using this VM to check the splash.
  boot.plymouth = {
    theme = "plotiphar";
    themePackages = [ (pkgs.callPackage ../../pkgs/plymouth-plotiphar-theme { }) ];
    extraConfig = "DeviceTimeout=5";
  };
}
