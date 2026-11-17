# Broadcom WiFi for Intel iMacs, picking the driver from the chip at boot.
#
# Apple used two families across these years:
#   - BCM4360 / BCM4352 (14e4:43a0, 14e4:43b1): proprietary `wl` only (as on
#     the 2013 MacBook Air, see ../julia-nixbook-air/broadcom-wl.nix).
#   - BCM43602 / BCM4350 and friends: in-kernel brcmfmac with linux-firmware.
# Rather than guess per model, brcmfmac loads on its own as usual, and `wl`
# is loaded only when a wl-only chip is present. bcma is blacklisted because
# it otherwise claims the 4360 and blocks wl.
#
# Not for T2 Macs (2018+ MacBooks, iMac Pro, 2019+ iMacs): their BCM4364/4377
# need firmware copied out of macOS, see hosts/plotiphar-imac.
{ config, lib, pkgs, ... }:
{
  hardware.enableRedistributableFirmware = true;

  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  boot.blacklistedKernelModules = [ "wl" "b43" "bcma" "ssb" "brcmsmac" ];

  systemd.services.broadcom-wl-select = {
    description = "Load the wl driver for wl-only Broadcom WiFi chips";
    wantedBy = [ "multi-user.target" ];
    before = [ "NetworkManager.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for dev in /sys/bus/pci/devices/*; do
        [ "$(cat "$dev/vendor")" = 0x14e4 ] || continue
        case "$(cat "$dev/device")" in
          0x43a0|0x43b1)
            echo "wl-only Broadcom chip at $dev, loading wl"
            ${pkgs.kmod}/bin/modprobe wl
            exit 0 ;;
        esac
      done
      echo "no wl-only Broadcom chip; leaving it to brcmfmac"
    '';
  };

  # Match by name so the allowance survives version bumps.
  nixpkgs.config.allowInsecurePredicate = pkg:
    lib.hasPrefix "broadcom-sta" (lib.getName pkg);
}
