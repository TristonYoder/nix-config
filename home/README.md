# Home Manager Configurations

User environment configurations managed with [Home Manager](https://github.com/nix-community/home-manager).

## Table of Contents

- [Overview](#overview)
- [User Configurations](#user-configurations)
- [Usage](#usage)
  - [Add Packages](#add-packages)
  - [Configure Applications](#configure-applications)
  - [macOS Homebrew Casks](#macos-homebrew-casks)
  - [Mac App Store Apps](#mac-app-store-apps)
  - [Shell Aliases](#shell-aliases)
  - [System Defaults (macOS)](#system-defaults-macos)
- [Applying Changes](#applying-changes)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)

## Overview

Home Manager provides declarative user environment management across NixOS and macOS, including:

- Shell configuration (zsh with Oh My Zsh & Powerlevel10k)
- Git settings
- SSH configuration
- User packages
- Application configuration
- macOS-specific settings (Homebrew, Mac App Store, system defaults)

**Key benefit:** User configurations are integrated into system rebuilds - no separate home-manager command needed.

## User Configurations

### common.nix (Shared)

Shared configuration for all users across platforms.

**Includes:**
- Git configuration (user, email, aliases)
- Zsh with Oh My Zsh and Powerlevel10k theme
- SSH configuration
- Common packages (git, gh, vim, htop, etc.)
- Shell aliases and functions
- Development tools

### tyoder.nix (macOS User)

macOS-specific configuration extending common.nix.

**Includes:**
- macOS system defaults (Dock, Finder, keyboard)
- Homebrew cask management
- Mac App Store app management
- macOS-specific packages
- Touch ID configuration
- System activation scripts

**Homebrew apps:** 30+ applications
**Mac App Store apps:** 10+ applications

### tristonyoder.nix (NixOS User)

NixOS-specific configuration extending common.nix.

**Includes:**
- Linux-specific packages
- Desktop environment settings
- Development tools
- System integration

## Usage

### Add Packages

Edit the appropriate user file (`home/tyoder.nix` or `home/tristonyoder.nix`):

```nix
{
  home.packages = with pkgs; [
    neofetch
    htop
    ripgrep
    jq
  ];
}
```

### Configure Applications

```nix
{
  # Vim
  programs.vim = {
    enable = true;
    settings = {
      number = true;
      relativenumber = true;
    };
  };
  
  # Tmux
  programs.tmux = {
    enable = true;
    shortcut = "a";
    terminal = "screen-256color";
  };
  
  # Git (additional settings)
  programs.git.extraConfig = {
    diff.tool = "vimdiff";
    merge.tool = "vimdiff";
  };
}
```

### macOS Homebrew Casks

In `home/tyoder.nix`:

```nix
{
  homebrew.casks = [
    "firefox"
    "visual-studio-code"
    "discord"
    "spotify"
    "1password"
  ];
}
```

### Mac App Store Apps

In `home/tyoder.nix`:

```nix
{
  mas.apps = [
    { id = "441258766"; name = "Magnet"; }           # Window manager
    { id = "1147396723"; name = "WhatsApp"; }        # Messaging
    { id = "1480933944"; name = "Vimari"; }          # Vim for Safari
  ];
}
```

**Find app IDs:**
```bash
mas search "App Name"
```

### Shell Aliases

In `home/common.nix` (shared) or user-specific files:

```nix
{
  programs.zsh.shellAliases = {
    ll = "ls -alh";
    gs = "git status";
    rebuild = "sudo nixos-rebuild switch --flake ~/Projects/nix-config";
    
    # Custom aliases
    myip = "curl -s https://ipinfo.io/ip";
    weather = "curl -s wttr.in";
  };
}
```

### System Defaults (macOS)

In `home/tyoder.nix`:

```nix
{
  targets.darwin.defaults = {
    # Dock settings
    "com.apple.dock" = {
      autohide = true;
      show-recents = false;
      tilesize = 48;
    };
    
    # Finder settings
    "com.apple.finder" = {
      ShowPathbar = true;
      ShowStatusBar = true;
      AppleShowAllFiles = true;
    };
    
    # Global settings
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };
  };
}
```

## Applying Changes

### Integrated with System Rebuilds

Home Manager is integrated into system configuration, so regular rebuilds apply changes:

```bash
# NixOS (includes Home Manager)
sudo nixos-rebuild switch --flake .

# macOS (includes Home Manager)
darwin-rebuild switch --flake .
```

### Home Manager Only (if needed)

```bash
# Update just Home Manager without system changes
home-manager switch --flake .

# Or use configured alias
rebuild-home
```

## Common Tasks

### Update Powerlevel10k Theme

```bash
# Run the configuration wizard
p10k configure

# This updates p10k.zsh with your preferences
# Commit the changes to version control
git add home/p10k.zsh
git commit -m "Update p10k theme configuration"
```

### Find Package Names

```bash
# Search for packages
nix search nixpkgs firefox

# Search for Homebrew casks (macOS)
brew search firefox

# Find Mac App Store IDs
mas search "App Name"
```

### Configure New Application

1. Check if there's a Home Manager module: https://nix-community.github.io/home-manager/options.xhtml
2. If yes, use `programs.<name>` or `services.<name>`
3. If no, add to `home.packages` and configure manually

Example:
```nix
{
  # Home Manager module exists
  programs.alacritty = {
    enable = true;
    settings = {
      font.size = 12;
    };
  };
  
  # No module, manual config
  home.packages = [ pkgs.app ];
  home.file.".config/app/config.yaml".text = ''
    setting: value
  '';
}
```

### Add Fonts

```nix
{
  home.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
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

### Homebrew Casks Not Installing (macOS)

```bash
# Install Homebrew first
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add to PATH (usually in ~/.zshrc)
eval "$(/opt/homebrew/bin/brew shellenv)"

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

# Log out and back in for changes to take effect
```

### Powerlevel10k Not Loading

```bash
# Check if p10k.zsh exists
ls -la ~/Projects/nix-config/home/p10k.zsh

# Source it manually (temporary fix)
source ~/Projects/nix-config/home/p10k.zsh

# Or reconfigure
p10k configure
```

### Home Manager Build Errors

```bash
# Check syntax
nix flake check

# Build without applying
home-manager build --flake .

# View detailed errors
home-manager switch --flake . --show-trace
```

## Custom Modules

### homebrew.nix

Custom Home Manager module for declarative Homebrew cask management on macOS.

**Usage:**
```nix
{
  homebrew = {
    enable = true;
    casks = [ "firefox" "visual-studio-code" ];
  };
}
```

### mas.nix

Custom Home Manager module for Mac App Store app management.

**Usage:**
```nix
{
  mas = {
    enable = true;
    apps = [
      { id = "441258766"; name = "Magnet"; }
    ];
  };
}
```

## Best Practices

1. **Use common.nix for shared settings** - Put settings used across all platforms in common.nix
2. **Platform-specific in user files** - macOS-specific in tyoder.nix, Linux-specific in tristonyoder.nix
3. **Test changes first** - Use `--dry-run` or build before switching
4. **Document custom configuration** - Add comments for non-obvious settings
5. **Version control themes** - Commit p10k.zsh for consistency across machines

## Additional Resources

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.xhtml)
- [Homebrew](https://brew.sh/)
- [Mac App Store CLI (mas)](https://github.com/mas-cli/mas)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Oh My Zsh](https://ohmyz.sh/)
- [Main README](../README.md) - Repository overview

---

**Users:** 2 (tyoder on macOS, tristonyoder on NixOS)  
**Platforms:** NixOS + macOS  
**Integration:** Flake-based, auto-applied with system rebuilds
