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

    # Force XWayland to start eagerly at login so DISPLAY is always set.
    # Without this, NVIDIA proprietary drivers leave XWayland on-demand,
    # causing Qt apps with hardcoded QT_QPA_PLATFORM=xcb to crash.
    systemd.tmpfiles.rules = [
      "d /tmp/.X11-unix 1777 root root -"
    ];
    systemd.user.services.xwayland-init = {
      description = "Force XWayland initialization";
      wantedBy = [ "graphical-session.target" ];
      after = [ "plasma-kwin_wayland.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.xdpyinfo}/bin/xdpyinfo -display :0";
        SuccessExitStatus = "0 1";
      };
    };

    # QtWebEngine for Plasma widgets that embed web content
    environment.systemPackages = [ pkgs.kdePackages.qtwebengine ];

    # Bluetooth
    hardware.bluetooth.enable = true;

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
