{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.guestKiosk;

  # cage is a Wayland compositor that runs a single fullscreen app with no
  # window manager chrome and nothing else reachable -- exactly what a kiosk
  # session needs. Firefox --kiosk hides the toolbar/tab bar/address bar.
  kioskScript = pkgs.writeShellScript "guest-kiosk-start" ''
    exec ${pkgs.cage}/bin/cage -- ${pkgs.firefox}/bin/firefox --kiosk "${cfg.url}"
  '';

  # Custom SDDM session, selectable from the greeter's session dropdown.
  # providedSessions must list the .desktop basename -- required by the
  # display-manager module to validate/link the session in.
  kioskSessionPackage = pkgs.writeTextFile {
    name = "guest-kiosk-session";
    destination = "/share/wayland-sessions/guest-kiosk.desktop";
    text = ''
      [Desktop Entry]
      Name=Guest (Kiosk)
      Comment=Locked-down browser session for guests
      Exec=${kioskScript}
      Type=Application
    '';
  } // {
    providedSessions = [ "guest-kiosk" ];
  };
in
{
  options.modules.system.guestKiosk = {
    enable = mkEnableOption "Passwordless guest account that logs into a locked-down kiosk browser session";

    url = mkOption {
      type = types.str;
      default = "https://apps.theyoder.family";
      description = "URL the kiosk browser opens to on login.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.modules.system.desktop.enable;
        message = "modules.system.guestKiosk.enable requires modules.system.desktop.enable (SDDM).";
      }
    ];

    users.users.guest = {
      isNormalUser = true;
      description = "Guest";
      hashedPassword = "";
      createHome = true;
      home = "/home/guest";
    };

    # Accounts with an empty password hash can log in with no password at the
    # SDDM greeter / local console. Only "guest" (above) has an empty hash --
    # every other account keeps a real password hash, so this doesn't weaken
    # login for anyone else.
    security.pam.services.login.allowNullPassword = true;

    services.displayManager.sessionPackages = [ kioskSessionPackage ];
  };
}
