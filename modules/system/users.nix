{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.users;
in
{
  options.modules.system.users = {
    enable = mkEnableOption "User account configuration";
    
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
      homeDirectory = "/data/${cfg.mainUser.name}/home";
    };
    
    # Caroline Yoder user account
    users.users.carolineyoder = {
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
      homeDirectory = "/data/carolineyoder/home";
    };
    
    # Create data directories with proper permissions for Nextcloud access
    systemd.tmpfiles.rules = [
      # Main data directory
      "d /data 0755 root root -"
      
      # User directories with nextcloud group access
      "d /data/tristonyoder 0755 tristonyoder nextcloud -"
      "d /data/carolineyoder 0755 carolineyoder nextcloud -"
      
      # User home directories (now the actual home directories)
      "d /data/tristonyoder/home 0755 tristonyoder nextcloud -"
      "d /data/carolineyoder/home 0755 carolineyoder nextcloud -"
      
      # Ensure proper SELinux contexts for Nextcloud access
      "Z /data/tristonyoder/home 0755 tristonyoder nextcloud -"
      "Z /data/carolineyoder/home 0755 carolineyoder nextcloud -"
    ];
    
  };
}

