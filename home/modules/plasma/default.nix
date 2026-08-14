# Shared KDE Plasma 6 look and layout, via plasma-manager.
#
# This is the desktop that grew up by hand on tristons-nixbook-pro. It is a
# macOS-shaped Plasma: global menu bar top-left, tray and clock top-right,
# floating centered dock at the bottom, and window buttons on the left. On the
# MacBooks the keyd Command<->Control swap (set per-host) puts every stock
# `Meta+` shortcut under the physical Command key, which is the other half of
# why it feels the way it does.
#
# plasma-manager rebuilds the panels from this file at every login: its startup
# script deletes plasma-org.kde.plasma.desktop-appletsrc and replays a
# generated layout.js. Panels are therefore fully declarative. Everything else
# (themes, kwin, screen locker) is written additively, so settings not named
# here keep whatever the machine already had. Set `programs.plasma.overrideConfig`
# to make that strict — but note it deletes the KDE config files on activation.
#
# The theme assets themselves are packaged in ./themes.nix.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.modules.plasma;

  themes = import ./themes.nix { inherit pkgs; };

  # Tray contents, in the order Plasma lists them. `extra` is the set of
  # applets explicitly enabled beyond the built-in defaults.
  trayItems = [
    "org.kde.plasma.cameraindicator"
    "org.kde.plasma.clipboard"
    "org.kde.plasma.devicenotifier"
    "org.kde.plasma.manage-inputmethod"
    "org.kde.plasma.mediacontroller"
    "org.kde.plasma.notifications"
    "org.kde.kscreen"
    "org.kde.plasma.battery"
    "org.kde.plasma.bluetooth"
    "org.kde.plasma.brightness"
    "org.kde.plasma.keyboardindicator"
    "org.kde.plasma.keyboardlayout"
    "org.kde.plasma.networkmanagement"
    "org.kde.plasma.volume"
    "org.kde.plasma.weather"
  ];

  systemTray = {
    systemTray.items.extra = trayItems;
    # Note: per-tray-applet config (e.g. battery showPercentage) is accepted by
    # plasma-manager's `items.configs` but silently dropped — the Plasma
    # scripting API has no support for nested containments, so its emitter is
    # commented out upstream. Set those few by hand in System Settings.
  };

  # Global menu bar. Left-aligned, sits opposite the tray.
  menuBarPanel = screen: {
    inherit screen;
    location = "top";
    alignment = "left";
    height = 40;
    hiding = "dodgewindows";
    opacity = "adaptive";
    widgets = [ "org.kde.plasma.appmenu" ];
  };

  # Tray + clock, right-aligned on the same top edge as the menu bar.
  statusPanel = screen: {
    inherit screen;
    location = "top";
    alignment = "right";
    height = 40;
    hiding = "dodgewindows";
    opacity = "adaptive";
    widgets = [
      systemTray
      "org.kde.plasma.digitalclock"
    ];
  };

  # The dock: floating, centered, sized to its contents.
  dockPanel = screen: {
    inherit screen;
    location = "bottom";
    alignment = "center";
    height = 50;
    floating = true;
    lengthMode = "fit";
    hiding = "windowsgobelow";
    opacity = "adaptive";
    widgets = [
      "org.kde.plasma.kickoff"
      "org.kde.plasma.showdesktop"
      "org.kde.plasma.icontasks"
    ];
  };
in
{
  options.modules.plasma = {
    enable = mkEnableOption "Shared KDE Plasma 6 look and layout";

    externalMonitor = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Also lay out panels on screen 1. Hosts that regularly drive a second
        display want this; leave it off on single-screen hosts so Plasma
        doesn't create panels for a screen that never appears.

        The second screen gets a pager and the global menu on its top-left
        panel, matching how it is used in practice.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Theme assets land on XDG_DATA_DIRS via the Home Manager profile, which is
    # where Plasma looks for global themes, decorations and plasmoids.
    home.packages = [
      themes.ant-dark
      themes.andromeda-launcher
      themes.kde-control-station

      # Ant-Dark is a folder-icon theme: its index.theme inherits
      # Reversal-dark, then Papirus-Dark, for everything else. Upstream ships
      # only the folder icons, whereas the KDE Store build that was installed
      # by hand on nixbook-pro also bundled ~2800 app icons of its own with no
      # git source to package. Providing the inherited themes covers the same
      # ground reproducibly — app icons will resolve to Reversal/Papirus rather
      # than that bundle, so a handful will look different from the machine
      # this was captured on.
      pkgs.reversal-icon-theme
      pkgs.papirus-icon-theme
    ];

    programs.plasma = {
      enable = true;

      workspace = {
        lookAndFeel = "Ant-Dark";
        theme = "Ant-Dark";
        iconTheme = "Ant-Dark";
        # Ant-Dark ships its own .colors scheme, but the desktop actually runs
        # on BreezeDark with Breeze widgets — only the shell, decoration and
        # icons are Ant. Changing either of these visibly changes application
        # chrome, so they are pinned deliberately.
        colorScheme = "BreezeDark";
        widgetStyle = "Breeze";

        cursor.theme = "breeze_cursors";

        splashScreen = {
          engine = "KSplashQML";
          theme = "Ant-Dark";
        };

        windowDecorations = {
          library = "org.kde.kwin.aurorae";
          theme = "__aurorae__svg__Ant-Dark";
        };
      };

      kwin = {
        # macOS traffic-light arrangement: everything on the left, nothing on
        # the right. Mirrors ButtonsOnLeft=XAI_M_SEH.
        titlebarButtons = {
          left = [
            "close"
            "maximize"
            "minimize"
            "spacer"
            "more-window-actions"
            "spacer"
            "on-all-desktops"
            "hide-from-screencast"
            "help"
          ];
          right = [ ];
        };

        virtualDesktops = {
          number = 1;
          rows = 1;
        };

        # The 25/50/25 custom tiling preset can't be shared: Plasma keys tile
        # layouts by virtual-desktop and screen UUID, both of which are
        # generated per machine. Only the padding is portable.
        tiling.padding = 4;
      };

      kscreenlocker.passwordRequiredDelay = 30;

      panels =
        [
          (menuBarPanel 0)
          (statusPanel 0)
          (dockPanel 0)
        ]
        ++ optionals cfg.externalMonitor [
          ((menuBarPanel 1) // {
            widgets = [
              "org.kde.plasma.pager"
              "org.kde.plasma.showdesktop"
              "org.kde.plasma.appmenu"
            ];
          })
          (statusPanel 1)
          (dockPanel 1)
        ];

      # Global shortcuts are deliberately left unmanaged. Every binding on
      # nixbook-pro is a Plasma default — the Mac-like feel comes from the keyd
      # Command<->Control swap in the host config, not from rebound keys.
      # Managing them here would only add noise that drifts from upstream
      # defaults on each Plasma release.
    };
  };
}
