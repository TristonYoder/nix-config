{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hardware.appleT2;
in
{
  options.modules.hardware.appleT2 = {
    enable = mkEnableOption "Apple T2 supplemental hardware configuration";

    # Set to true once t2-wifi-firmware.age has been committed to secrets/.
    # See hosts/tristons-nixbook-t2/INSTALL.md for extraction steps.
    wifiFirmware = mkOption {
      type = types.bool;
      default = false;
      description = "Deploy Broadcom WiFi firmware from the t2-wifi-firmware agenix secret.";
    };
  };

  config = mkIf cfg.enable {
    # Pre-built T2 kernel packages — avoids local kernel compilation on rebuild
    nix.settings = {
      substituters = mkAfter [ "https://cache.soopy.moe" ];
      trusted-public-keys = mkAfter [
        "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="
      ];
    };

    # Trackpad regression introduced in kernel 6.1+
    boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

    # Broadcom WiFi firmware: only active after t2-wifi-firmware.age is committed.
    # The tarball is extracted from macOS, encrypted with agenix, and deployed here.
    # WiFi works on the first boot after wifiFirmware = true and a rebuild.
    system.activationScripts.t2-wifi-firmware = mkIf cfg.wifiFirmware {
      deps = [ "agenix" ];
      text = ''
        firmware_tar="${config.age.secrets.t2-wifi-firmware.path}"
        if [ -f "$firmware_tar" ]; then
          mkdir -p /lib/firmware
          ${pkgs.gnutar}/bin/tar xzf "$firmware_tar" -C /lib/firmware/ 2>/dev/null
        fi
      '';
    };

    # Touch Bar — tiny-dfr drives the display, shows F1–F12 by default.
    # Hold Fn for media keys. Settings can be overridden per-host via
    # hardware.apple.touchBar.settings (see nixos/modules/hardware/apple-touchbar.nix).
    hardware.apple.touchBar.enable = true;

    # Unload apple-bce before suspend; macOS Sonoma firmware changes broke S3
    # resume and cause kernel oops without this workaround.
    systemd.services.t2-apple-bce-suspend = {
      description = "T2 apple-bce suspend compatibility";
      wantedBy = [ "sleep.target" ];
      before = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.kmod}/bin/modprobe -r apple-bce";
        ExecStop = "${pkgs.kmod}/bin/modprobe apple-bce";
        RemainAfterExit = "yes";
      };
    };
  };
}
