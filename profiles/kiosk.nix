# Kiosk Profile
# Minimal single-purpose signage host: no desktop environment, just an
# auto-logged-in X11 session running one fullscreen Chromium instance
# per connected display output.

{ config, pkgs, lib, ... }:
{
  # =============================================================================
  # HARDWARE MODULES
  # =============================================================================

  # Default: normal systemd-boot/EFI. Kiosk hosts whose bootloader is owned by
  # something else (e.g. the Pi 5's own firmware/config.txt boot chain) override
  # this to false in their own host config — see hosts/stage-plotiphar.
  modules.hardware.boot.enable = lib.mkDefault true;

  # =============================================================================
  # SYSTEM MODULES
  # =============================================================================

  modules.system.core.enable = lib.mkDefault true;
  modules.system.networking.enable = lib.mkDefault true;
  modules.system.users.enable = lib.mkDefault true;
  # This is an appliance, not a desktop for the admin user — no GUI apps needed
  # on the admin account. Kiosk display packages live under modules.services.kiosk.
  modules.system.users.mainUser.packages = lib.mkDefault [ ];
  # KDE/desktop module not used — kiosk display is handled directly below.
  modules.system.desktop.enable = lib.mkDefault false;

  # =============================================================================
  # DISPLAY: minimal X11 + autologin + openbox
  # =============================================================================
  # X11 (not Wayland) specifically because Chromium's
  # --window-position/--window-size + a bare Openbox WM is the reliable,
  # well-documented way to pin one browser window per physical monitor.

  hardware.graphics.enable = lib.mkDefault true;

  services.xserver = {
    enable = true;
    videoDrivers = [ "modesetting" ];
    displayManager.lightdm.enable = true;
    windowManager.openbox.enable = true;
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = config.modules.services.kiosk.browserKiosk.user;
  };
  services.displayManager.defaultSession = "none+openbox";

  # Boot splash — same theme as profiles/desktop.nix. A kiosk sits on a wall
  # showing its boot process to whoever's nearby otherwise; worth covering.
  boot.plymouth = {
    enable = true;
    theme = "colorful";
    themePackages = with pkgs; [
      (adi1090x-plymouth-themes.override {
        selected_themes = [ "colorful" ];
      })
    ];
    extraConfig = ''
      [Daemon]
      Theme=colorful
      ShowDelay=0
      DeviceTimeout=5
    '';
  };
  boot.kernelParams = [ "splash" ];

  # =============================================================================
  # KIOSK BROWSER
  # =============================================================================

  modules.services.kiosk.browserKiosk.enable = lib.mkDefault true;

  # =============================================================================
  # REMOTE MANAGEMENT
  # =============================================================================

  modules.services.infrastructure.tailscale.enable = lib.mkDefault true;
  modules.services.development.vscode-server.enable = lib.mkDefault true;

  # =============================================================================
  # DNS
  # =============================================================================

  networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];
}
