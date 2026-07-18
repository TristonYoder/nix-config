{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.infrastructure.libvirt;
  domain = config.networking.domain;
in
{
  options.modules.services.infrastructure.libvirt = {
    enable = mkEnableOption "libvirt QEMU/KVM virtualization host";

    macosVm = {
      enable = mkEnableOption "macOS VM on QEMU/KVM";

      name = mkOption {
        type = types.str;
        default = "macos-vm";
        description = "Domain name for the macOS VM.";
      };

      vcpu = mkOption {
        type = types.int;
        default = 4;
        description = "Number of vCPUs.";
      };

      memory = mkOption {
        type = types.int;
        default = 8192;
        description = "Memory in MB.";
      };

      diskPath = mkOption {
        type = types.str;
        default = "/data/vms/macos-vm/disk.qcow2";
        description = "Path to the VM disk image.";
      };

      diskSizeG = mkOption {
        type = types.int;
        default = 100;
        description = "Disk image size in GB (applied by quickemu on first boot).";
      };

      macosVersion = mkOption {
        type = types.str;
        default = "sequoia";
        description = "macOS release version (passed to quickemu).";
      };

      tailscaleIp = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Tailscale IP of the macOS VM. When set, a vHost entry is created so
          Caddy can reverse-proxy to services running inside the VM.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu;
        runAsRoot = true;
        swtpm.enable = true;
        ovmf.enable = true;
      };
    };

    environment.systemPackages = with pkgs; [
      libvirt
      virt-manager
      virt-viewer
    ];

    users.users.tristonyoder.extraGroups = [ "libvirtd" ];

    # ── quickemu config for the macOS VM ─────────────────────────────────────
    environment.etc."quickemu/macos-vm.conf" = mkIf cfg.macosVm.enable {
      text = ''
        # macOS VM — managed by Nix; DO NOT EDIT MANUALLY
        # Launch: quickemu --vm /etc/quickemu/macos-vm.conf [--macvtap] [--display spice]
        guest_os="macos"
        macos_release="${cfg.macosVm.macosVersion}"
        disk_img="${cfg.macosVm.diskPath}"
        img_size="${toString cfg.macosVm.diskSizeG}G"
      '';
    };

    # ── macOS installer fetcher (quickget) ────────────────────────────────────
    # Downloads the macOS recovery image and OpenCore bootloader from Apple's
    # softwareupdate catalog — same mechanism as fetch-macOS.py from Docker-OSX
    # and macOS-Simple-KVM. Runs as tristonyoder so assets land in the right
    # place for quickemu to find them.
    #
    # Trigger on demand — only needed once (or on macOS version upgrade):
    #   sudo systemctl start get-macos-installer
    #   sudo journalctl -u get-macos-installer -f    # watch progress (~12 GB)
    systemd.services."get-macos-installer" = mkIf cfg.macosVm.enable {
      description = "Download macOS ${cfg.macosVm.macosVersion} installer + OpenCore";
      path = [ pkgs.quickemu pkgs.coreutils pkgs.bash ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "tristonyoder";
      };
      script = ''
        set -e
        echo "==> Downloading macOS ${cfg.macosVm.macosVersion} installer..."
        echo "    (this may take a while — the installer is several GB)"
        quickget --download macos ${cfg.macosVm.macosVersion}
        echo "==> Done. Installer ready for:"
        echo "    quickemu --vm /etc/quickemu/macos-vm.conf --macvtap --display spice"
      '';
    };

    # ── vHosts: wire Caddy to proxy services inside the VM ────────────────────
    modules.services.vHosts.hosts = mkIf (cfg.macosVm.enable && cfg.macosVm.tailscaleIp != null) {
      "macos-vm.${domain}" = {
        reverseProxyHost = cfg.macosVm.tailscaleIp;
        reverseProxyPort = 80;
        reverseProxySSL = false;
        displayName = "macOS VM";
        category = "infrastructure";
        icon = "apple";
        monitor = false;
      };
    };
  };
}
