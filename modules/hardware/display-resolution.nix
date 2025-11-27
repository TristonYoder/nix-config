{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hardware.displayResolution;
  
  # Hostname-based resolution mapping
  hostResolutions = {
    "david" = "1920x1080";
    "tristons-desk" = "1920x1080";
    "tristons-nixbook" = "2560x1600";
    "pits" = "1920x1080";  # Default for headless/edge
  };
  
  # Determine resolution based on hostname
  autoDetectResolution = hostResolutions.${config.networking.hostName} or "1920x1080";
in
{
  options.modules.hardware.displayResolution = {
    enable = mkEnableOption "Automatic display resolution configuration for Plymouth";
    
    resolution = mkOption {
      type = types.str;
      default = autoDetectResolution;
      description = "Display resolution for boot (format: WIDTHxHEIGHT)";
      example = "2560x1600";
    };
    
    autoDetect = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically detect resolution based on hostname";
    };
  };

  config = mkIf cfg.enable {
    boot.kernelParams = [
      "video=${cfg.resolution}"
      "vga=current"
    ];
    
    # Optional: Add assertion to ensure resolution format is valid
    assertions = [
      {
        assertion = builtins.match "[0-9]+x[0-9]+" cfg.resolution != null;
        message = "Display resolution must be in format WIDTHxHEIGHT (e.g., 1920x1080)";
      }
    ];
  };
}