{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.users;
in
{
  options.modules.system.users = {
    enable = mkEnableOption "User account configuration";

    useDataDrive = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Symlink /home/username to /data/username/home.
        Enable on hosts with a separate /data partition (e.g., servers with ZFS).
      '';
    };

    mainUser = {
      name = mkOption {
        type = types.str;
        default = "tristonyoder";
        description = "Main user account name";
      };

      description = mkOption {
        type = types.str;
        default = "Triston Yoder";
        description = "User description/full name";
      };

      extraGroups = mkOption {
        type = types.listOf types.str;
        default = [ "networkmanager" "wheel" "docker" "nextcloud" ];
        description = "Additional groups for main user";
      };

      packages = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [
          firefox
          bitwarden-desktop
          vscode
          _1password-gui
          _1password-cli
          compose2nix
        ];
        description = "Packages for main user";
      };

      sshKeys = mkOption {
        type = types.listOf types.str;
        default = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz"
        ];
        description = "SSH public keys for main user";
      };
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.mainUser.name} = {
      isNormalUser = true;
      description = cfg.mainUser.description;
      extraGroups = cfg.mainUser.extraGroups;
      packages = cfg.mainUser.packages;
      openssh.authorizedKeys.keys = cfg.mainUser.sshKeys;
      home = "/home/${cfg.mainUser.name}";
    };

    # Caroline Yoder user account (only on hosts with data drive)
    users.users.carolineyoder = mkIf cfg.useDataDrive {
      isNormalUser = true;
      description = "Caroline Yoder";
      extraGroups = [ "nextcloud" ];
      packages = with pkgs; [
        firefox
        bitwarden-desktop
        _1password-gui
      ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz"  # Same key as tristonyoder for now
      ];
      home = "/home/carolineyoder";
    };

    # Data drive setup: symlink /home to /data for persistent storage
    systemd.tmpfiles.rules = mkIf cfg.useDataDrive [
      # Main data directory
      "d /data 0755 root root -"

      # User directories with nextcloud group access
      "d /data/tristonyoder 0755 tristonyoder nextcloud -"
      "d /data/carolineyoder 0755 carolineyoder nextcloud -"

      # Actual home directories on data drive
      "d /data/tristonyoder/home 0755 tristonyoder nextcloud -"
      "d /data/carolineyoder/home 0755 carolineyoder nextcloud -"

      # Symlinks from standard /home paths to data drive
      # L+ creates symlink, replacing existing file/directory if needed
      "L+ /home/tristonyoder - - - - /data/tristonyoder/home"
      "L+ /home/carolineyoder - - - - /data/carolineyoder/home"

      # Ensure proper permissions on data directories
      "Z /data/tristonyoder/home 0755 tristonyoder nextcloud -"
      "Z /data/carolineyoder/home 0755 carolineyoder nextcloud -"
    ];

  };
}

