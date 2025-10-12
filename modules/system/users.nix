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
        default = [ "networkmanager" "wheel" "docker" ];
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
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.mainUser.name} = {
      isNormalUser = true;
      description = cfg.mainUser.description;
      extraGroups = cfg.mainUser.extraGroups;
      packages = cfg.mainUser.packages;
    };
  };
}

