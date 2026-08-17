# PXE/iPXE netboot variant of the barebones installer — same Tailscale/SSH
# logic as configuration.nix (the ISO variant), but built as a kernel +
# initrd pair instead of an ISO9660 filesystem, since that's what PXE needs.
#
# nixpkgs' netbootIpxeScript (system.build.netbootRamdisk) bundles the
# *entire* squashed Nix store into the initrd itself — there's no separate
# squashfs fetch at boot, so only two files need to be served: the kernel
# and that initrd. netbootBundle below packages both plus the generated
# netboot.ipxe script (which references them by the relative names "bzImage"
# and "initrd") into one directory, ready to publish alongside the ISOs.
#
# Build (from a NixOS host, e.g. david):
#   nix build .#nixosConfigurations.installer-netboot.config.system.build.netbootBundle --refresh
{ pkgs, modulesPath, config, ... }:

{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ./common.nix
  ];

  nixpkgs.config.allowUnfree = true;

  system.build.netbootBundle = pkgs.linkFarm "nixos-installer-netboot" [
    {
      name = "bzImage";
      path = "${config.system.build.kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
    }
    {
      name = "initrd";
      path = "${config.system.build.netbootRamdisk}/initrd";
    }
    {
      name = "netboot.ipxe";
      path = "${config.system.build.netbootIpxeScript}/netboot.ipxe";
    }
  ];
}
