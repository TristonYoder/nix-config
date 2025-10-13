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

    # OpenSSH
    services.openssh.enable = true;
    services.openssh.settings.PasswordAuthentication = lib.mkDefault true;
  };
}

