# Settings shared by every MacBook running NixOS: keyboard layout, lid
# behaviour, and optional SMC fan control. Model-specific quirks (T2 suspend,
# Broadcom WiFi, ...) stay in their own modules or the host config.
{ config, lib, ... }:

with lib;
let
  cfg = config.modules.hardware.appleLaptop;
in
{
  options.modules.hardware.appleLaptop = {
    enable = mkEnableOption "common MacBook settings";

    swapCommandControl = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Swap Command and Control with keyd, so the key next to the spacebar
        acts as Control (Ctrl+C, Ctrl+V) the way Command does on macOS.
        Works the same in Wayland, X11 and the TTY.
      '';
    };

    fanControl = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run mbpfan for SMC fan control. Useful on pre-T2 Intel MacBooks,
        whose firmware fan curve runs hot under Linux. T2 machines manage
        fans through the T2 chip and don't need it.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.keyd = mkIf cfg.swapCommandControl {
      enable = true;
      keyboards.default = {
        ids = [ "*" ];
        settings.main = {
          leftmeta = "leftcontrol";
          leftcontrol = "leftmeta";
          rightmeta = "rightcontrol";
          rightcontrol = "rightmeta";
        };
      };
    };

    services.mbpfan.enable = mkIf cfg.fanControl true;

    # Close the lid -> sleep, on battery or charger, like macOS.
    services.logind = {
      lidSwitch = mkDefault "suspend";
      lidSwitchExternalPower = mkDefault "suspend";
    };
  };
}
