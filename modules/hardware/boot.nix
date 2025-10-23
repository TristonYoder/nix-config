{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hardware.boot;
in
{
  options.modules.hardware.boot = {
    enable = mkEnableOption "Bootloader configuration (systemd-boot)";
    
    configurationLimit = mkOption {
      type = types.int;
      default = 50;
      description = "Number of boot generations to keep";
    };
  };

  config = mkIf cfg.enable {
    boot.loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = cfg.configurationLimit;
      };
      
      efi.canTouchEfiVariables = true;
    };
  };
}

