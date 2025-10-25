# macOS-specific Home Manager Configuration
# Shared between tyoder and tristonyoder on macOS (Darwin)

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # MACOS-SPECIFIC PACKAGES
  # =============================================================================
  
  home.packages = with pkgs; [
    # macOS-specific tools
    syncthing
    tailscale
    element-desktop
  ];
  
  # =============================================================================
  # MACOS-SPECIFIC SHELL ALIASES
  # =============================================================================
  
  programs.zsh = {
    shellAliases = {
      # macOS DNS flush
      dnsflush = "sudo killall -HUP mDNSResponder;sudo killall mDNSResponderHelper;sudo dscacheutil -flushcache";
      
      # Home manager switch shortcut (with auto-reload)
      hms = "cd ~/Projects/nix-config && sudo darwin-rebuild switch --flake . && exec zsh";
      hmswitch = "cd ~/Projects/nix-config && sudo darwin-rebuild switch --flake . && exec zsh";
    };
  };
  
  # =============================================================================
  # MACOS ACTIVATION SCRIPTS
  # =============================================================================
  
  # Create symlinks in system Applications folder
  home.activation.linkApplications = lib.hm.dag.entryAfter ["installPackages"] ''
    verboseEcho "Linking Nix-managed applications to /Applications/..."
    
    # Create Applications directory if it doesn't exist
    run mkdir -p /Applications
    
    # Link each Nix-managed application
    for app in ${config.home.homeDirectory}/.nix-profile/Applications/*.app; do
      if [[ -e "$app" ]]; then
        app_name=$(basename "$app")
        verboseEcho "Linking $app_name to /Applications/"
        # Remove existing link if it exists
        if [[ -L "/Applications/$app_name" ]]; then
          run rm "/Applications/$app_name"
        fi
        # Create symlink
        run ln -sf "$app" "/Applications/$app_name"
        # Refresh Finder cache for this app
        run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$app_name" 2>/dev/null || true
      fi
    done
  '';
  
  # Desktop refresh after system configuration changes
  home.activation.refreshDesktop = lib.hm.dag.entryAfter ["linkApplications"] ''
    verboseEcho "Refreshing desktop and dock..."
    
    # Refresh Launch Services database
    run /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true
    
    # Restart Dock to apply changes
    run /usr/bin/killall Dock 2>/dev/null || true
    
    # Restart Finder to refresh desktop
    run /usr/bin/killall Finder 2>/dev/null || true
    
    verboseEcho "Desktop refresh complete"
  '';
  
  # =============================================================================
  # MACOS SYSTEM DEFAULTS
  # =============================================================================
  
  targets.darwin.defaults = {
    # Dock Configuration
    "com.apple.dock" = {
      autohide = false;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.0;
      show-recents = false;
      show-process-indicators = true;
      tilesize = 36;
      largesize = 64;
      magnification = false;
      mineffect = "genie";
      minimize-to-application = true;
      orientation = "bottom";
      showhidden = true;
      static-only = false;
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
    };
    
    # Finder Configuration
    "com.apple.finder" = {
      AppleShowAllFiles = true;
      FXDefaultSearchScope = "SCcf";
      FXPreferredViewStyle = "Nlsv";
      ShowPathbar = true;
      ShowStatusBar = true;
      ShowTabView = true;
      SidebarWidth = 200;
      NewWindowTarget = "PfHm";
      NewWindowTargetPath = "file://${config.home.homeDirectory}";
      _FXShowPosixPathInTitle = true;
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;
    };
    
    # Global Domain (System-wide settings)
    NSGlobalDomain = {
      AppleKeyboardUIMode = 3;
      KeyRepeat = 1;
      InitialKeyRepeat = 15;
      ApplePressAndHoldEnabled = false;
      "com.apple.trackpad.scaling" = 1.5;
      "com.apple.trackpad.trackpadCornerClickBehavior" = 1;
      "com.apple.trackpad.enableSecondaryClick" = true;
      AppleShowScrollBars = "Always";
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      NSTableViewDefaultSizeMode = 2;
      AppleInterfaceStyle = "Dark";
      AppleAccentColor = 1;
      AppleFontSmoothing = 1;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticTextCompletionEnabled = false;
    };
    
    # Screensaver
    "com.apple.screensaver" = {
      askForPassword = 1;
      askForPasswordDelay = 0;
    };
    
    # Screenshots
    "com.apple.screencapture" = {
      location = "${config.home.homeDirectory}/Desktop/Screenshots";
      type = "png";
      disable-shadow = true;
    };
    
    # Desktop Services
    "com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
    };
    
    # TextEdit
    "com.apple.TextEdit" = {
      RichText = 0;
    };
    
    # Activity Monitor
    "com.apple.ActivityMonitor" = {
      ShowCategory = 0;
      SortColumn = "CPUUsage";
      SortDirection = 0;
    };
    
    # Safari
    "com.apple.Safari" = {
      IncludeDevelopMenu = true;
      IncludeInternalDebugMenu = true;
      WebKitDeveloperExtrasEnabledPreferenceKey = true;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
      WebKitPreferences.developerExtrasEnabled = true;
    };
  };
  
  # =============================================================================
  # HOMEBREW CONFIGURATION
  # =============================================================================
  
  homebrew = {
    enable = true;
    onActivation.autoUpdate = true;
    onActivation.cleanup = "none";
    
    casks = [
      # Development & Productivity
      "1password"
      "cursor"
      "bartender"
      "firefox"
      "bitwarden"
      "visual-studio-code"
      "iterm2"
      
      # System Utilities
      "hazel"
      "lunar"
      "tailscale"
      
      # Communication & Media
      "fantastical"
      "microsoft-teams"
      "vlc"
      "asana"
      
      # Creative & Design
      "affine"
      "sketchup"
      
      # Cloud & Storage
      "google-drive"
      "gcloud-cli"
      "google-cloud-sdk"
      
      # 3D Printing & Hardware
      "orcaslicer"
      "raspberry-pi-imager"
      "balenaetcher"
      
      # Production
      "companion"
      "propresenter"
      "freeshow"
      
      # Other useful apps
      "notion"
      "keycastr"
      "readdle-spark"
      "termius"
      "home-assistant"
      "sonos"
      "moonlight"
      "logos"
      "fontbase"
      "goodsync"
      "4k-video-downloader"
      "adobe-creative-cloud"
      "microsoft-auto-update"
      
      # Browsers & Web
      "google-chrome"
      
      # Microsoft Office Suite
      "microsoft-office"
      
      # Communication & Productivity
      "spotify"
      "mattermost"
      
      # System & Utilities
      "trezor-suite"
      "logi-options-plus"
      
      # Creative & Design
      "shapr3d"
    ];
  };
  
  # =============================================================================
  # MAC APP STORE
  # =============================================================================
  
  mas = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
    };
    apps = [
      { id = "441258766"; name = "Magnet"; }
      { id = "1663047912"; name = "Screens 5"; }
      { id = "1565946661"; name = "FloatingHead"; }
      { id = "1569813296"; name = "1Password for Safari"; }
      { id = "634148309"; name = "Logic Pro"; }
      { id = "424390742"; name = "Compressor"; }
      { id = "1453365242"; name = "Brother P-touch Editor"; }
      { id = "1462114288"; name = "Grammarly for Safari"; }
      { id = "1559269364"; name = "Notion Web Clipper"; }
      { id = "1246969117"; name = "Steam Link"; }
      { id = "1295203466"; name = "Windows App"; }
    ];
  };
}
