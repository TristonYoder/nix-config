{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.desktop;
in
{
  options.modules.system.desktop = {
    enable = mkEnableOption "Desktop environment (KDE Plasma 6)";
    
    enableX11 = mkOption {
      type = types.bool;
      default = true;
      description = "Enable X11 windowing system";
    };
    
    enableSound = mkOption {
      type = types.bool;
      default = true;
      description = "Enable sound with PipeWire";
    };
  };

  config = mkIf cfg.enable {
    # Enable the X11 windowing system
    services.xserver.enable = mkIf cfg.enableX11 true;

    # Enable the KDE Plasma Desktop Environment
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;

    # Sound configuration with PipeWire
    services.pulseaudio.enable = mkIf cfg.enableSound false;
    security.rtkit.enable = mkIf cfg.enableSound true;
    services.pipewire = mkIf cfg.enableSound {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}

