{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hardware.nvidia;
in
{
  options.modules.hardware.nvidia = {
    enable = mkEnableOption "NVIDIA graphics driver";
    
    enableModesetting = mkOption {
      type = types.bool;
      default = true;
      description = "Enable modesetting for NVIDIA";
    };
    
    enableSettings = mkOption {
      type = types.bool;
      default = true;
      description = "Enable NVIDIA settings GUI";
    };
    
    useOpenSource = mkOption {
      type = types.bool;
      default = false;
      description = "Use open-source NVIDIA driver";
    };
    
    package = mkOption {
      type = types.package;
      default = config.boot.kernelPackages.nvidiaPackages.stable;
      defaultText = literalExpression "config.boot.kernelPackages.nvidiaPackages.stable";
      description = ''
        Driver package. Current branches drop older GPUs (595+ ignores Pascal
        and Maxwell), so those need a legacy branch such as
        `nvidiaPackages.legacy_580`.
      '';
    };

    enable32Bit = mkOption {
      type = types.bool;
      default = true;
      description = "Enable 32-bit graphics support";
    };
  };

  config = mkIf cfg.enable {
    # Graphics/OpenGL
    hardware.graphics = {
      enable = true;
      enable32Bit = cfg.enable32Bit;
    };

    # NVIDIA driver
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      modesetting.enable = cfg.enableModesetting;
      nvidiaSettings = cfg.enableSettings;
      open = cfg.useOpenSource;
      package = cfg.package;
    };
  };
}

