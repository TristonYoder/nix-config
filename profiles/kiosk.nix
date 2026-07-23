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
    # A kiosk display is meant to always be showing something — disable DPMS
    # power-down and the blank-screen screensaver at the X server level, not
    # just in the session, so nothing (greeter included) can blank it.
    serverFlagsSection = ''
      Option "BlankTime" "0"
      Option "StandbyTime" "0"
      Option "SuspendTime" "0"
      Option "OffTime" "0"
    '';
  };

  # Belt-and-suspenders: some drivers ignore serverFlagsSection, so also
  # disable the screensaver/DPMS explicitly once the kiosk session starts.
  # Also hide the (unused, no-mouse-attached-in-practice) cursor immediately
  # rather than waiting on unclutter's normal idle timeout — a signage
  # display should never show a pointer at all.
  services.xserver.displayManager.sessionCommands = ''
    ${pkgs.xset}/bin/xset s off
    ${pkgs.xset}/bin/xset -dpms
    ${pkgs.unclutter-xfixes}/bin/unclutter --timeout 0 --jitter 0 --start-hidden &
  '';

  services.displayManager.autoLogin = {
    enable = true;
    user = config.modules.services.kiosk.browserKiosk.user;
  };
  services.displayManager.defaultSession = "none+openbox";

  # Boot splash — same theme as profiles/desktop.nix. A kiosk sits on a wall
  # showing its boot process to whoever's nearby otherwise; worth covering.
  boot.plymouth = {
    enable = lib.mkDefault true;
    # Generic default for this shared profile — kiosk hosts with their own
    # brand identity (e.g. stage-plotiphar) override theme/themePackages in
    # their host config rather than changing this default for everyone.
    theme = lib.mkDefault "colorful";
    themePackages = lib.mkDefault (with pkgs; [
      (adi1090x-plymouth-themes.override {
        selected_themes = [ "colorful" ];
      })
    ]);
    # Appended *inside* the [Daemon] section the module already generates
    # from theme/showDelay — must not re-open "[Daemon]" itself (see the
    # stage-plotiphar override for the DeviceTimeout-mismatch this caused).
    extraConfig = lib.mkDefault "DeviceTimeout=5";
  };
  boot.kernelParams = [
    "splash"
    # A kiosk display should never show boot text, even when Plymouth loses
    # the race for the console (see stage-plotiphar's fbcon/vc4 timing notes).
    # "auto" tries to detect whether Plymouth "owns" the screen and still
    # printed status text here — "false" hides it unconditionally instead.
    # Both the plain and rd.-prefixed (initrd-scoped) forms are needed;
    # they're independent settings for the two systemd instances, and this
    # host's own base modules already contribute an rd.systemd.show_status
    # of their own earlier in the list, so ours needs to come after to win
    # (kernel cmdline is last-value-wins for duplicate keys).
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
    "vt.global_cursor_default=0"
  ];
  # NOTE: common/linux.nix sets this to 3 as a plain (non-mkDefault) value,
  # which wins over this — kept as documentation of intent, but see the
  # show_status params above for what's actually suppressing console text.
  boot.consoleLogLevel = lib.mkDefault 0;
  # No login prompt should ever be visible on the signage output either —
  # SSH remains available regardless, and tty2+ still work for physical
  # debugging with a keyboard attached.
  systemd.services."getty@tty1".enable = lib.mkDefault false;

  # Plymouth's default trigger (multi-user.target) fires well before lightdm
  # has actually started Xorg painting — on stage-plotiphar this left a gap
  # where the splash quit and boot/console text was visible again before X
  # took over. Ordering after display-manager.service narrows that gap.
  systemd.services.plymouth-quit.after = [ "display-manager.service" ];
  systemd.services.plymouth-quit-wait.after = [ "display-manager.service" ];

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
