{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.core;
in
{
  options.modules.system.core = {
    enable = mkEnableOption "Core system configuration";
    
    timeZone = mkOption {
      type = types.str;
      default = "America/Indiana/Indianapolis";
      description = "System timezone";
    };
    
    locale = mkOption {
      type = types.str;
      default = "en_US.UTF-8";
      description = "System locale";
    };
    
    enableZsh = mkOption {
      type = types.bool;
      default = true;
      description = "Enable and set zsh as default shell";
    };
    
    allowUnfree = mkOption {
      type = types.bool;
      default = true;
      description = "Allow unfree packages";
    };
    
    systemPackages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [ wget gh git zsh quickemu ];
      description = "System-wide packages";
    };
  };

  config = mkIf cfg.enable {
    # Nix settings
    nix = {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        warn-dirty = false;
      };
      
      # Automatic garbage collection
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 90d";
      };
    };

    # Time zone
    time.timeZone = cfg.timeZone;

    # Internationalization
    i18n.defaultLocale = cfg.locale;
    i18n.extraLocaleSettings = {
      LC_ADDRESS = cfg.locale;
      LC_IDENTIFICATION = cfg.locale;
      LC_MEASUREMENT = cfg.locale;
      LC_MONETARY = cfg.locale;
      LC_NAME = cfg.locale;
      LC_NUMERIC = cfg.locale;
      LC_PAPER = cfg.locale;
      LC_TELEPHONE = cfg.locale;
      LC_TIME = cfg.locale;
    };

    # Allow unfree packages
    nixpkgs.config.allowUnfree = cfg.allowUnfree;

    # System packages
    environment.systemPackages = cfg.systemPackages;

    # Zsh configuration
    programs.zsh.enable = mkIf cfg.enableZsh true;
    users.defaultUserShell = mkIf cfg.enableZsh pkgs.zsh;

    # Fonts configuration for Powerlevel10k (GUI terminals)
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        # Nerd Fonts with icons and glyphs for Powerlevel10k
        nerd-fonts.meslo-lg
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
        nerd-fonts.hack
        
        # Additional fonts for better terminal experience
        noto-fonts
        noto-fonts-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
        
        # Terminus font for console (tty) - has some powerline support
        terminus_font
      ];
      
      fontconfig = {
        defaultFonts = {
          monospace = [ "MesloLGS NF" "FiraCode Nerd Font" "JetBrainsMono Nerd Font" ];
          sansSerif = [ "Noto Sans" "Liberation Sans" ];
          serif = [ "Noto Serif" "Liberation Serif" ];
          emoji = [ "Noto Color Emoji" ];
        };
      };
    };

    # Console (tty) font configuration
    # NOTE: The Linux console cannot display Nerd Fonts or most Unicode glyphs.
    # This provides the best available console font with some powerline support.
    # For full Powerlevel10k experience, use SSH or a GUI terminal emulator.
    console = {
      # Terminus is one of the best console fonts with partial powerline support
      font = "ter-v32n";  # Terminus font, 32px height (16x32), normal weight
      # Other good options:
      # "ter-v28n" - 28px height (14x28)
      # "ter-v24n" - 24px height (12x24)
      # "ter-v20n" - 20px height (10x20)
      # "ter-v16n" - 16px height (8x16) - smaller, more text on screen
      
      packages = [ pkgs.terminus_font ];
      
      # Enable early KMS (Kernel Mode Setting) for better console experience
      earlySetup = true;
      
      # UTF-8 support for better character rendering
      keyMap = "us";
    };

    # OpenSSH
    services.openssh.enable = true;
    services.openssh.settings.PasswordAuthentication = lib.mkDefault false;
  };
}

