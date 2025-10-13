# Home Manager Configurations

User environment configurations managed with [Home Manager](https://github.com/nix-community/home-manager).

## Overview

Home Manager provides declarative user environment management across NixOS and macOS, including:
- Shell configuration (zsh, bash)
- Git settings
- SSH configuration
- User packages
- Application configuration
- macOS-specific settings (Homebrew, Mac App Store)

## Structure

```
home/
├── common.nix         # Shared user settings (all platforms)
├── tyoder.nix         # macOS user configuration
├── tristonyoder.nix   # NixOS user configuration
├── p10k.zsh           # Powerlevel10k theme configuration
└── modules/
    ├── homebrew.nix   # Custom Homebrew Home Manager module
    └── mas.nix        # Custom Mac App Store module
```

## User Configurations

### common.nix (Shared)

Shared configuration for all users across platforms:

**Includes:**
- Git configuration (user, email, aliases)
- Zsh with Oh My Zsh
- Powerlevel10k theme
- SSH configuration
- Common packages (git, gh, vim, htop, etc.)
- Shell aliases and functions
- Development tools

**Example:**
```nix
{
  programs.git = {
    enable = true;
    userName = "Your Name";
    userEmail = "you@example.com";
  };
  
  programs.zsh = {
    enable = true;
    oh-my-zsh.enable = true;
    oh-my-zsh.theme = "powerlevel10k/powerlevel10k";
  };
}
```

### tyoder.nix (macOS User)

macOS-specific configuration extending common.nix:

**Includes:**
- macOS system defaults (Dock, Finder, keyboard)
- Homebrew cask management
- Mac App Store app management
- macOS-specific packages
- Touch ID configuration
- System activation scripts

**Example:**
```nix
{
  imports = [ ./common.nix ];
  
  # Homebrew casks
  homebrew.casks = [
    "firefox"
    "visual-studio-code"
    "docker"
  ];
  
  # Mac App Store apps
  mas.apps = [
    { id = "441258766"; name = "Magnet"; }
    { id = "497799835"; name = "Xcode"; }
  ];
  
  # System defaults
  targets.darwin.defaults = {
    "com.apple.dock".autohide = true;
    "com.apple.finder".ShowPathbar = true;
  };
}
```

### tristonyoder.nix (NixOS User)

NixOS-specific configuration extending common.nix:

**Includes:**
- Linux-specific packages
- Desktop environment settings
- Development tools
- System integration

**Example:**
```nix
{
  imports = [ ./common.nix ];
  
  # Additional Linux packages
  home.packages = with pkgs; [
    firefox
    vscode
  ];
}
```

## Usage

### Add Packages

Edit the appropriate user file:

```nix
{
  home.packages = with pkgs; [
    neofetch
    htop
    ripgrep
  ];
}
```

### Configure Applications

```nix
{
  programs.vim = {
    enable = true;
    settings = {
      number = true;
      relativenumber = true;
    };
  };
  
  programs.tmux = {
    enable = true;
    shortcut = "a";
    terminal = "screen-256color";
  };
}
```

### macOS Homebrew Casks

```nix
{
  homebrew.casks = [
    "firefox"
    "visual-studio-code"
    "discord"
    "spotify"
  ];
}
```

### Mac App Store Apps

```nix
{
  mas.apps = [
    { id = "441258766"; name = "Magnet"; }           # Window manager
    { id = "1147396723"; name = "WhatsApp"; }        # Messaging
    { id = "1480933944"; name = "Vimari"; }          # Vim for Safari
  ];
}
```

### Shell Aliases

```nix
{
  programs.zsh.shellAliases = {
    ll = "ls -alh";
    gs = "git status";
    rebuild = "sudo nixos-rebuild switch --flake .";
  };
}
```

### System Defaults (macOS)

```nix
{
  targets.darwin.defaults = {
    # Dock
    "com.apple.dock" = {
      autohide = true;
      show-recents = false;
      tilesize = 48;
    };
    
    # Finder
    "com.apple.finder" = {
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    
    # Global
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };
  };
}
```

## Applying Changes

### NixOS

Home Manager is integrated into the system configuration:

```bash
# Rebuild system (includes Home Manager)
sudo nixos-rebuild switch --flake .
```

### macOS

```bash
# Rebuild Darwin (includes Home Manager)
darwin-rebuild switch --flake .
```

### Home Manager Only

```bash
# Update just Home Manager (without system)
home-manager switch --flake .
```

## Common Tasks

### Update Home Manager

```bash
# Update flake inputs
nix flake update

# Rebuild
sudo nixos-rebuild switch --flake .  # NixOS
darwin-rebuild switch --flake .      # macOS
```

### Find Package Names

```bash
# Search for packages
nix search nixpkgs firefox

# Search for Homebrew casks
brew search firefox

# Find Mac App Store IDs
mas search "App Name"
```

### Configure New Application

1. Check if there's a Home Manager module: https://nix-community.github.io/home-manager/options.xhtml
2. If yes, use `programs.<name>` or `services.<name>`
3. If no, add to `home.packages` and configure manually

## Powerlevel10k Theme

The Powerlevel10k zsh theme configuration is in `p10k.zsh`.

### Reconfigure Theme

```bash
# Run the configuration wizard
p10k configure
```

This will update `p10k.zsh` with your preferences.

## Custom Modules

### homebrew.nix

Custom Home Manager module for declarative Homebrew cask management on macOS.

**Usage:**
```nix
{
  homebrew.casks = [ "firefox" "visual-studio-code" ];
}
```

### mas.nix

Custom Home Manager module for Mac App Store app management.

**Usage:**
```nix
{
  mas.apps = [
    { id = "441258766"; name = "Magnet"; }
  ];
}
```

## Troubleshooting

### Changes Not Applied

```bash
# Force rebuild
sudo nixos-rebuild switch --flake . --recreate-lock-file

# macOS: Some settings require logout
killall Dock && killall Finder
# Or log out and back in
```

### Homebrew Casks Not Installing

```bash
# Install Homebrew first (macOS)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then rebuild
darwin-rebuild switch --flake .
```

### Mac App Store Apps Not Installing

```bash
# Install mas CLI tool
brew install mas

# Sign in to App Store
mas signin your-email@example.com

# Then rebuild
darwin-rebuild switch --flake .
```

### Shell Not Using Zsh

```bash
# Check current shell
echo $SHELL

# Change to zsh (if needed)
chsh -s $(which zsh)

# Log out and back in
```

### Powerlevel10k Not Loading

```bash
# Ensure p10k.zsh exists
ls -la ~/Projects/david-nixos/home/p10k.zsh

# Source it manually (temporary)
source ~/Projects/david-nixos/home/p10k.zsh

# Or reconfigure
p10k configure
```

## Best Practices

1. **Use common.nix for shared settings** - Put settings used across all platforms in common.nix
2. **Platform-specific in user files** - macOS-specific in tyoder.nix, Linux-specific in tristonyoder.nix
3. **Test changes locally first** - Use `--dry-run` or build before switching
4. **Document custom configuration** - Add comments for non-obvious settings
5. **Version control p10k.zsh** - Commit theme configuration for consistency

## Resources

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.xhtml)
- [Homebrew](https://brew.sh/)
- [Mac App Store CLI](https://github.com/mas-cli/mas)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Oh My Zsh](https://ohmyz.sh/)

---

**Users:** 2 (tyoder on macOS, tristonyoder on NixOS)  
**Platforms:** NixOS + macOS  
**Integration:** Flake-based Home Manager  
**Last Updated:** October 13, 2025

