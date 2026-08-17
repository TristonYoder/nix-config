# PXE netboot installer service: serves a menu of NixOS netboot images.
#
# DHCP itself is NOT managed here — it lives in Unifi. Point Unifi's DHCP
# option 67 (Bootfile name) at "menu.efi" (UEFI) or "menu.kpxe" (legacy BIOS)
# served by this host's TFTP (option 66 -> this host's LAN IP).
#
# Those two files aren't stock iPXE binaries — they're built with the boot
# menu script baked in at compile time (embedScript), so the very first PXE
# stage already knows how to show the menu with no second DHCP round trip or
# proxyDHCP/userclass tagging tricks required. Selecting an entry chainloads
# that image's own ipxe script over HTTP, which fetches its kernel/initrd/
# squashfs (TFTP only ever serves the small chainloader binaries, never the
# multi-hundred-MB image artifacts).
#
# Adding an image: define another `nixosConfigurations.<name>` netboot build
# (see hosts/netboot-installer/*.nix for examples) and add an entry to
# `images` below.

{ config, lib, pkgs, self ? null, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.netboot;
  hostUrl = "http://${config.networking.hostName}.theyoder.family:${toString cfg.httpPort}";

  buildImage = name: image:
    let
      installer = self.nixosConfigurations.${image.nixosConfiguration}.config;
      kernelTarget = installer.system.boot.loader.kernelFile;
    in
    pkgs.runCommand "netboot-image-${name}" { } ''
      mkdir -p $out
      cp ${installer.system.build.kernel}/${kernelTarget} $out/bzImage
      cp ${installer.system.build.netbootRamdisk}/initrd $out/initrd
      cp ${installer.system.build.squashfsStore} $out/nix-store.squashfs
      cat > $out/boot.ipxe <<EOF
      #!ipxe
      kernel ${hostUrl}/${name}/bzImage init=${installer.system.build.toplevel}/init initrd=initrd ${toString installer.boot.kernelParams}
      initrd ${hostUrl}/${name}/initrd
      boot
      EOF
    '';

  menuScript = pkgs.writeText "menu.ipxe" ''
    #!ipxe
    :menu
    menu NixOS netboot installer
    ${concatStringsSep "\n" (mapAttrsToList (name: image: "item ${name} ${image.label}") cfg.images)}
    item shell Drop to iPXE shell
    choose --timeout 30000 --default ${head (attrNames cfg.images)} target && goto ''${target} || goto menu

    ${concatStringsSep "\n" (mapAttrsToList (name: _: ''
      :${name}
      chain ${hostUrl}/${name}/boot.ipxe
      goto menu
    '') cfg.images)}

    :shell
    shell
    goto menu
  '';
in
{
  options.modules.services.infrastructure.netboot = {
    enable = mkEnableOption "PXE netboot installer (TFTP menu chainloader + HTTP artifact server)";

    httpPort = mkOption {
      type = types.port;
      default = 8078;
      description = "Port the netboot HTTP artifact server listens on.";
    };

    images = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          nixosConfiguration = mkOption {
            type = types.str;
            description = "Name of the flake's nixosConfigurations entry to serve (must use a netboot installer module).";
          };
          label = mkOption {
            type = types.str;
            description = "Human-readable label shown in the iPXE boot menu.";
          };
        };
      });
      default = {
        nixos = {
          nixosConfiguration = "netboot-installer";
          label = "NixOS installer (generic x86_64)";
        };
        nixos-t2 = {
          nixosConfiguration = "netboot-installer-t2";
          label = "NixOS installer (T2 MacBook Pro)";
        };
      };
      description = "Netboot images to serve, keyed by a short URL-safe name.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = self != null;
        message = "modules.services.infrastructure.netboot.enable requires `self` passed via this host's specialArgs (see flake.nix).";
      }
    ];

    # Document root for atftpd: only the two menu-embedded iPXE binaries.
    # Everything else (kernels, initrds, squashfs, per-image scripts) is
    # served over HTTP via nginx below.
    services.atftpd = {
      enable = true;
      root =
        let menuIpxe = pkgs.ipxe.override { embedScript = menuScript; };
        in pkgs.runCommand "netboot-tftproot" { } ''
          mkdir -p $out
          cp ${menuIpxe}/ipxe.efi $out/menu.efi
          cp ${menuIpxe}/undionly.kpxe $out/menu.kpxe
        '';
    };

    networking.firewall.allowedUDPPorts = [ 69 ];
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];

    services.nginx = {
      enable = true;
      virtualHosts."netboot" = {
        listen = [{ addr = "0.0.0.0"; port = cfg.httpPort; }];
        root = pkgs.linkFarm "netboot-httproot" (
          mapAttrsToList (name: image: { inherit name; path = buildImage name image; }) cfg.images
        );
        extraConfig = "autoindex on;";
      };
    };
  };
}
