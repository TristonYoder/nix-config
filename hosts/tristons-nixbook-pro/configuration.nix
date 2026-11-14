# Configuration for tristons-nixbook-pro
# NixOS on 2019 T2 MacBook Pro 16,1 (dual boot alongside macOS)

{ config, pkgs, lib, nixos-hardware, ... }:
{
  # ===========================================================================
  # SYSTEM IDENTIFICATION
  # ===========================================================================

  networking.hostName = "tristons-nixbook-pro";
  system.stateVersion = "25.05";

  # ===========================================================================
  # HARDWARE
  # ===========================================================================

  # WiFi firmware fetched from macOS Sonoma installer via Asahi extraction scripts.
  # Fully reproducible — no manual firmware extraction from macOS required.
  hardware.apple-t2.firmware = {
    enable = true;
    version = "sonoma";
  };

  hardware.apple.touchBar.settings.MediaLayerDefault = true;

  # nixos-hardware's stable T2 kernel pairs nixpkgs' linux_6_18 with a t2linux
  # patch set pinned in early 2026; t2linux itself has moved on to 7.x. By
  # 6.18.57 several patches (i915 quirk, applesmc) no longer apply, and the
  # "latest" channel points at linux 7.0, which nixpkgs has removed. Pin 6.18
  # to the point release this laptop last built and ran. Remove once
  # nixos-hardware refreshes stable.json or moves to the t2bce/7.x stack.
  #
  # generic.nix passes its own argsOverride (extraMeta) to kernel.override,
  # which would replace a pin set on linux_6_18 beforehand, so the pin is
  # merged into whatever argsOverride that call carries.
  boot.kernelPackages =
    let
      pin = rec {
        version = "6.18.38";
        modDirVersion = version;
        src = pkgs.fetchurl {
          url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
          hash = "sha256-rCblCKvVbp+LiYcrbhDEn8gjvMcNgGil2FBMGnxP8EU=";
        };
      };
      pinnedLinux = pkgs.linux_6_18 // {
        override = args: pkgs.linux_6_18.override (args // {
          argsOverride = (args.argsOverride or { }) // pin;
        });
      };
    in
    lib.mkForce (pkgs.linuxPackagesFor (
      pkgs.callPackage "${nixos-hardware}/apple/t2/pkgs/linux-t2/generic.nix" { } {
        kernel = pinnedLinux;
        patchesFile = "${nixos-hardware}/apple/t2/pkgs/linux-t2/stable.json";
      }
    ));

  # Intel UHD 630 VA-API support.
  hardware.graphics = {
    extraPackages = with pkgs; [ intel-media-driver ];
    extraPackages32 = with pkgs.pkgsi686Linux; [ intel-media-driver ];
  };

  # steamwebhelper (CEF) crashes on NixOS because pressure-vessel's ldconfig
  # can't detect host library architecture and fails to overlay the 32-bit Mesa
  # GBM driver into the container. Disabling browser HW acceleration in
  # steamwebhelper avoids the GPU init path that hits the CHECK(false) crash.
  # Games are unaffected — only Steam's own UI uses software rendering.
  environment.sessionVariables.STEAM_DISABLE_BROWSER_HARDWARE_ACCELERATION = "1";

  # systemd-boot on the shared EFI partition with macOS
  modules.hardware.boot.enable = true;

  # ===========================================================================
  # KEYBOARD — SWAP COMMAND AND CONTROL
  # ===========================================================================

  # Mac keyboard has Command next to spacebar. Swap at kernel level so it
  # works across Wayland, X11, and TTY.
  # Command/Control swap and lid-sleep defaults (modules/hardware/apple-laptop.nix)
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
  # POWER MANAGEMENT
  # ===========================================================================

  modules.hardware.t2Suspend = {
    enable = true;
    mode = "workaround";
  };

  # logind/sleep settings for t2Suspend workaround mode.
  # Kept here (not in the module) to avoid the shared module referencing
  # version-sensitive option paths.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = true;
    AllowHibernation = false;
    AllowSuspendThenHibernate = false;
    AllowHybridSleep = false;
  };

  services.logind = {
    lidSwitch = "suspend";
    lidSwitchExternalPower = "suspend";
    settings.Login = {
      HandleSuspendKey = "suspend";
      HandleHibernateKey = "ignore";
    };
  };

  # ===========================================================================
  # PACKAGES
  # ===========================================================================

  # Desktop apps (firefox, vlc, vscode) come from profiles/workstation.nix.
  environment.systemPackages = with pkgs; [
    nfs-utils
  ];

  home-manager.users.tristonyoder.modules.appShortcuts.enable = true;

  # ===========================================================================
  # DESKTOP
  # ===========================================================================

  # Declarative Plasma look and panel layout. This host is where the layout
  # originated, so it is the reference implementation — see home/modules/plasma.
  home-manager.users.tristonyoder.modules.plasma = {
    enable = true;
    externalMonitor = true;
  };

  # HiDPI on the built-in Retina panel. Host-specific: this would be wrong on
  # any of the other Plasma hosts, so it stays out of the shared module.
  home-manager.users.tristonyoder.programs.plasma.configFile.kwinrc.Xwayland.Scale = 1.5;

  # Passwordless guest account -> locked-down kiosk browser at apps.theyoder.family
  modules.system.guestKiosk.enable = true;

  # Unattended RustDesk, enrolled in CortenDesk (secrets encrypted to this host).
  modules.services.infrastructure.rustdeskAgent.enable = true;
}
