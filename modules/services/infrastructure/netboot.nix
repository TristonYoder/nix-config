# PXE netboot installer service.
#
# DHCP itself is NOT managed here — it lives in Unifi. Point Unifi's DHCP
# options at this host:
#   Option 66 (TFTP server name)  -> this host's LAN IP
#   Option 67 (Bootfile name)     -> "ipxe.efi" (or "undionly.kpxe" for legacy BIOS)
#
# Boot flow: PXE firmware -> TFTP fetches iPXE -> iPXE chainloads
# http://<this host>:<httpPort>/netboot.ipxe -> fetches kernel/initrd/squashfs
# over HTTP (TFTP is only used for the small initial chainloader, never the
# multi-hundred-MB netboot artifacts).

{ config, lib, pkgs, self, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.netboot;
  installer = self.nixosConfigurations.netboot-installer.config;
  kernelTarget = installer.system.boot.loader.kernelFile;
in
{
  options.modules.services.infrastructure.netboot = {
    enable = mkEnableOption "PXE netboot installer (TFTP chainloader + HTTP artifact server)";

    httpPort = mkOption {
      type = types.port;
      default = 8078;
      description = "Port the netboot HTTP artifact server listens on.";
    };
  };

  config = mkIf cfg.enable {
    # Document root for atftpd, built from the iPXE firmware images so both
    # legacy BIOS (undionly.kpxe) and UEFI (ipxe.efi) clients can chainload.
    services.atftpd = {
      enable = true;
      root = pkgs.runCommand "netboot-tftproot" { } ''
        mkdir -p $out
        cp ${pkgs.ipxe}/ipxe.efi $out/ipxe.efi
        cp ${pkgs.ipxe}/undionly.kpxe $out/undionly.kpxe
      '';
    };

    networking.firewall.allowedUDPPorts = [ 69 ];
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];

    services.nginx = {
      enable = true;
      virtualHosts."netboot" = {
        listen = [{ addr = "0.0.0.0"; port = cfg.httpPort; }];
        root = pkgs.runCommand "netboot-httproot" { } ''
          mkdir -p $out
          cp ${installer.system.build.kernel}/${kernelTarget} $out/bzImage
          cp ${installer.system.build.netbootRamdisk}/initrd $out/initrd
          cp ${installer.system.build.squashfsStore} $out/nix-store.squashfs
          cat > $out/netboot.ipxe <<'EOF'
          #!ipxe
          kernel http://${config.networking.hostName}.theyoder.family:${toString cfg.httpPort}/bzImage init=${installer.system.build.toplevel}/init initrd=initrd ${toString installer.boot.kernelParams}
          initrd http://${config.networking.hostName}.theyoder.family:${toString cfg.httpPort}/initrd
          boot
          EOF
        '';
        extraConfig = "autoindex on;";
      };
    };
  };
}
