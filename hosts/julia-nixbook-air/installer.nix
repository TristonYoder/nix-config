# NixOS installer ISO for Julia-NixBook-Air (MacBook Air 2013, MacBookAir6,x)
#
# Same as the generic installer (Tailscale QR + key-only SSH, see
# ../installer/common.nix) plus the Broadcom BCM4360 WiFi driver. The
# in-kernel drivers (b43/brcmsmac) don't support the 4360, so this uses the
# proprietary `wl` driver (broadcom_sta).
#
# broadcom_sta is flagged insecure in nixpkgs (CVE-2019-9501/9502, unmaintained).
# There is no alternative driver for this chip; a USB or Ethernet adapter is
# the only way around it.
#
# Build (needs an x86_64-linux builder, e.g. david):
#   nix build .#nixosConfigurations.julia-nixbook-air-installer.config.system.build.isoImage --refresh
{ config, lib, ... }:
{
  imports = [ ../installer/configuration.nix ];

  boot.kernelModules = [ "wl" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.broadcom_sta ];
  boot.blacklistedKernelModules = [ "b43" "bcma" "ssb" "brcmsmac" "brcmfmac" ];

  nixpkgs.config.allowInsecurePredicate = pkg:
    lib.hasPrefix "broadcom-sta" (lib.getName pkg);

  # installation-cd-minimal enables wpa_supplicant; nmtui is easier for
  # joining WiFi by hand on first boot.
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  # mkOverride 40 beats the mkForce (50) in ../installer/configuration.nix.
  isoImage.isoBaseName = lib.mkOverride 40 "nixos-julia-nixbook-air-installer";
}
