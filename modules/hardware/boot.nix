{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hardware.boot;
in
{
  options.modules.hardware.boot = {
    enable = mkEnableOption "Bootloader configuration (systemd-boot with GRUB theming)";
    
    configurationLimit = mkOption {
      type = types.int;
      default = 50;
      description = "Number of boot generations to keep";
    };
    
    enableGrubTheme = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GRUB theme (Breeze)";
    };
    
    backgroundColor = mkOption {
      type = types.str;
      default = "#8275b4";
      description = "GRUB background color";
    };
  };

  config = mkIf cfg.enable {
    # Bootloader configuration
    boot.loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = cfg.configurationLimit;
      };
      
      efi.canTouchEfiVariables = true;
      
      grub = {
        efiSupport = true;
        splashMode = "normal";
        backgroundColor = cfg.backgroundColor;
        theme = mkIf cfg.enableGrubTheme "${pkgs.libsForQt5.breeze-grub}/grub/themes/breeze";
        extraEntriesBeforeNixOS = true;
      };
    };
  };
}

