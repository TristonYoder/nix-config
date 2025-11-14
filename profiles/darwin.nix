# Darwin (macOS) Profile
# Configuration for macOS machines using nix-darwin

{ config, pkgs, lib, ... }:

{
  # =============================================================================
  # NIX-DARWIN SYSTEM SETTINGS
  # =============================================================================
  
  # macOS system packages
  environment.systemPackages = with pkgs; [
    # Development tools
    git
    gh
    vim
    
    # Utilities
    wget
    curl
    htop
    tree
    
    # Storage & Sync
    syncthing
  ];
  
  # =============================================================================
  # HOMEBREW INTEGRATION
  # =============================================================================
  
  # Enable Homebrew integration (managed via home-manager)
  # This allows GUI apps that aren't available in nixpkgs
  
  # =============================================================================
  # SYSTEM PREFERENCES
  # =============================================================================
  
  # nix-daemon is now managed unconditionally by nix-darwin when nix.enable is on
  
  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;
  
  # Note: system.primaryUser is set in individual host configurations
  # (hosts/tyoder-mbp/configuration.nix or hosts/tristons-mbp/configuration.nix)
  
  # =============================================================================
  # NIX OPTIMIZATION (Darwin-safe method)
  # =============================================================================
  
  # Use automatic optimization instead of auto-optimise-store (which corrupts store on Darwin)
  nix.optimise.automatic = true;
  
  # =============================================================================
  # SHELL CONFIGURATION
  # =============================================================================
  
  # Use zsh as default shell
  programs.zsh.enable = true;
  
  # Set up zsh to work with nix-darwin
  environment.shells = [ pkgs.zsh ];
  
  # =============================================================================
  # FONTS
  # =============================================================================
  
  fonts.packages = with pkgs; [
    # Nerd Fonts (individual packages in new structure)
    nerd-fonts.fira-code
    nerd-fonts.meslo-lg
    nerd-fonts.roboto-mono
  ];
  
  # =============================================================================
  # SYNCTHING AUTO-START SERVICE
  # =============================================================================
  
  # Configure Syncthing to start automatically at login using launchd
  # This ensures Syncthing runs in the background after user login
  # Launch agents run in the user's context, so HOME is automatically set
  environment.launchAgents."com.syncthing.syncthing" = {
    enable = true;
    target = "com.syncthing.syncthing.plist";
    text = ''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.syncthing.syncthing</string>

  <key>ProgramArguments</key>
  <array>
    <string>${pkgs.syncthing}/bin/syncthing</string>
    <string>-no-browser</string>
    <string>-no-restart</string>
    <string>-logflags=0</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
    <key>Crashed</key>
    <true/>
  </dict>

  <key>ProcessType</key>
  <string>Background</string>

  <key>StandardErrorPath</key>
  <string>/tmp/syncthing.err.log</string>

  <key>StandardOutPath</key>
  <string>/tmp/syncthing.out.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${lib.concatStringsSep ":" [ "/usr/bin" "/bin" "/usr/sbin" "/sbin" "${pkgs.syncthing}/bin" ]}</string>
  </dict>
</dict>
</plist>
'';
  };
  
}

