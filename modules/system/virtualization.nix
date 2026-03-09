{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.virtualization;
in
{
  options.modules.system.virtualization = {
    enable = mkEnableOption "KVM/QEMU virtualization with libvirt";

    enableGUI = mkOption {
      type = types.bool;
      default = true;
      description = "Enable virt-manager GUI";
    };

    enableLookingGlass = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Looking Glass for GPU passthrough VM display";
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Users to add to libvirtd group";
    };
  };

  config = mkIf cfg.enable {
    # Enable virtualization
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        ovmf = {
          enable = true;
          packages = [ pkgs.OVMFFull.fd ];
        };
      };
    };

    # Enable IOMMU and KVM support
    boot.kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
    ];

    # Load VFIO modules for GPU passthrough capability
    boot.kernelModules = [ "vfio" "vfio_iommu_type1" "vfio_pci" ];

    # Virtualization tools
    environment.systemPackages = with pkgs; [
      qemu
      looking-glass-client
    ] ++ optionals cfg.enableGUI [
      virt-manager
      virt-viewer
    ];

    # Add users to libvirtd group
    users.users = listToAttrs (map (user: {
      name = user;
      value = {
        extraGroups = [ "libvirtd" ];
      };
    }) cfg.users);

    # Looking Glass configuration for GPU passthrough
    systemd.tmpfiles.rules = mkIf cfg.enableLookingGlass [
      "f /dev/shm/looking-glass 0660 ${head cfg.users} kvm -"
    ];
  };
}
