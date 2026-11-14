# Broadcom BCM4360 WiFi (MacBook Air 2013). Shared by the installed system and
# the installer ISO.
#
# The in-kernel drivers (b43/brcmsmac) don't support the 4360, so this uses the
# proprietary `wl` driver (broadcom_sta). nixpkgs flags it insecure
# (CVE-2019-9501/9502, unmaintained); there is no alternative driver for this
# chip short of a USB or Ethernet adapter.
{ config, lib, ... }:
{
  boot.kernelModules = [ "wl" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  boot.blacklistedKernelModules = [ "b43" "bcma" "ssb" "brcmsmac" "brcmfmac" ];

  # Match by name so the allowance survives version bumps.
  nixpkgs.config.allowInsecurePredicate = pkg:
    lib.hasPrefix "broadcom-sta" (lib.getName pkg);
}
