# PXE/iPXE netboot for the barebones NixOS installer (see hosts/installer/).
# Boots any PXE-capable client on `interface`'s VLAN straight into the
# installer, no USB stick required.
#
# Deliberately scoped: proxyDHCP + TFTP are bound to a single interface
# (`cfg.interface`, expected to be a VLAN-tagged link to the client subnet —
# see hosts/david/configuration.nix's vlan10). dnsmasq's own DNS resolver is
# disabled (`port = 0`) so this never competes with the real DHCP server
# (UniFi) or DNS (Technitium) already serving that network — it only
# answers PXE-specific queries, and only on that one interface.
#
# Boot files live in one shared directory (`cfg.bootFilesDir`), served two
# ways: TFTP (for the small iPXE chainload binaries every PXE ROM can fetch)
# and HTTP via the vHosts registry (for the installer kernel/initrd, which
# are too large to serve efficiently over TFTP). The iPXE binaries
# themselves come straight from nixpkgs and are symlinked in at activation.
#
# The kernel/initrd/netboot.ipxe come from this repo's
# nixosConfigurations.installer-netboot(-aarch64) flake outputs and are
# published into cfg.bootFilesDir/<x86_64|aarch64>/ separately (CI, same
# pattern as the nix-iso vHost for the ISO images) — one subdirectory per
# architecture, since x86_64 and aarch64 clients need different
# kernel/initrd pairs. nixpkgs' generated netboot.ipxe references its kernel
# and initrd by relative filename ("bzImage"/"initrd"), which iPXE resolves
# against the script's own URL — so dnsmasq just needs to send each client
# to the right architecture's netboot.ipxe and the relative fetches follow
# automatically.
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.pxeBoot;

  ipxeX86_64 = pkgs.ipxe;
  ipxeAarch64 = pkgs.pkgsCross.aarch64-multiplatform.ipxe;
in
{
  options.modules.services.infrastructure.pxeBoot = {
    enable = mkEnableOption "PXE/iPXE netboot for the barebones NixOS installer";

    interface = mkOption {
      type = types.str;
      default = "vlan10";
      description = ''
        Interface to bind proxyDHCP and TFTP to. Must have L2 adjacency to
        the client subnet — proxyDHCP only sees broadcast traffic on its
        own segment. Never set this to a Core Services interface.
      '';
    };

    subnet = mkOption {
      type = types.str;
      default = "10.150.10.0";
      description = "Network address of the client subnet reachable via `interface`.";
    };

    netmask = mkOption {
      type = types.str;
      default = "255.255.255.0";
      description = "Netmask of the client subnet reachable via `interface`.";
    };

    domain = mkOption {
      type = types.str;
      default = "pxe.${config.networking.domain}";
      description = "Domain the boot files (kernel/initrd/iPXE script) are served over HTTP from.";
    };

    bootFilesDir = mkOption {
      type = types.path;
      default = "/var/lib/tftpboot";
      description = ''
        Directory serving both TFTP and HTTP boot files. iPXE chainload
        binaries are symlinked directly under here automatically. The
        installer kernel/initrd/netboot.ipxe must be published separately
        (e.g. by CI) into <bootFilesDir>/x86_64/ and <bootFilesDir>/aarch64/
        as nixosConfigurations.installer-netboot(-aarch64)'s netbootBundle
        output — one subdirectory per architecture.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.dnsmasq = {
      enable = true;
      settings = {
        port = 0; # DNS off — Technitium already owns DNS on this network
        interface = [ cfg.interface ];
        bind-interfaces = true;
        except-interface = [ "lo" ];

        dhcp-range = [ "${cfg.subnet},proxy,${cfg.netmask}" ];

        enable-tftp = true;
        tftp-root = cfg.bootFilesDir;

        # RFC4578 client-architecture option (93) — pick the right
        # first-stage loader per PXE ROM without guessing.
        dhcp-match = [
          "set:bios,option:client-arch,0"
          "set:efi-x86_64,option:client-arch,7"
          "set:efi-x86_64,option:client-arch,9"
          "set:efi-arm64,option:client-arch,11"
        ];

        # iPXE identifies itself via a DHCP user-class on its second
        # request — once we see that, hand it the real boot script over
        # HTTP instead of re-serving the TFTP chainload binary. Split by
        # client-arch too (not just tag:ipxe) so x86_64 and aarch64 clients
        # land on their own netboot.ipxe with the matching kernel/initrd.
        dhcp-userclass = [ "set:ipxe,iPXE" ];

        dhcp-boot = [
          "tag:ipxe,tag:bios,http://${cfg.domain}/x86_64/netboot.ipxe"
          "tag:ipxe,tag:efi-x86_64,http://${cfg.domain}/x86_64/netboot.ipxe"
          "tag:ipxe,tag:efi-arm64,http://${cfg.domain}/aarch64/netboot.ipxe"
          "tag:!ipxe,tag:bios,undionly.kpxe"
          "tag:!ipxe,tag:efi-x86_64,ipxe-x86_64.efi"
          "tag:!ipxe,tag:efi-arm64,ipxe-aarch64.efi"
        ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.bootFilesDir} 0755 dnsmasq dnsmasq -"
      "L+ ${cfg.bootFilesDir}/undionly.kpxe - - - - ${ipxeX86_64}/undionly.kpxe"
      "L+ ${cfg.bootFilesDir}/ipxe-x86_64.efi - - - - ${ipxeX86_64}/ipxe.efi"
      "L+ ${cfg.bootFilesDir}/ipxe-aarch64.efi - - - - ${ipxeAarch64}/ipxe.efi"
    ];

    # HTTP side of cfg.bootFilesDir — kernel/initrd/netboot.ipxe. Internal
    # only (not `public`), same as the nix-iso vHost these installer
    # artifacts sit alongside.
    modules.services.vHosts.hosts.${cfg.domain} = {
      rawConfig = true;
      displayName = "PXE Boot";
      category = "infrastructure";
      monitor = false; # directory listing, not a service with a stable 200
      extraConfig = ''
        root * ${cfg.bootFilesDir}
        file_server browse
      '';
    };
  };
}
