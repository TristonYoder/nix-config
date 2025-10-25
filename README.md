# Multi-Host NixOS & Darwin Configuration

> A unified, flake-based configuration managing NixOS servers, desktops, and macOS machines with integrated Home Manager and automated CI/CD.

[![NixOS](https://img.shields.io/badge/NixOS-25.05-blue.svg)](https://nixos.org)
[![Flakes](https://img.shields.io/badge/Nix-Flakes-green.svg)](https://nixos.wiki/wiki/Flakes)
[![macOS](https://img.shields.io/badge/macOS-nix--darwin-blueviolet.svg)](https://github.com/LnL7/nix-darwin)

[![Test](https://github.com/TristonYoder/nix-config/actions/workflows/test-nixos-config.yml/badge.svg)](https://github.com/TristonYoder/nix-config/actions/workflows/test-nixos-config.yml)
[![Deploy](https://github.com/TristonYoder/nix-config/actions/workflows/deploy-nixos-config.yml/badge.svg)](https://github.com/TristonYoder/nix-config/actions/workflows/deploy-nixos-config.yml)

## Table of Contents

- [Managed Hosts](#managed-hosts)
- [Quick Start](#quick-start)
  - [NixOS](#nixos-hosts)
  - [macOS](#macos)
  - [Common Commands](#common-commands)
- [Configuration](#configuration)
  - [Enable Services](#enable-a-service)
  - [Add Packages](#add-packages)
  - [Customize Options](#customize-options)
- [Architecture](#architecture)
  - [Profiles](#profiles)
  - [Modules](#modules)
  - [Hosts](#hosts)
  - [Home Manager](#home-manager)
- [Documentation](#documentation)
- [Automation](#automated-deployment)
- [Examples](#configuration-examples)

## Managed Hosts

| Host | Type | Profile | Auto-Deploy | Purpose |
|------|------|---------|-------------|---------|
| **david** | NixOS Server | Server | ✅ | Full infrastructure stack |
| **pits** | NixOS Edge (Pi) | Edge | ✅ | Public-facing reverse proxy |
| **tristons-desk** | NixOS Desktop | Desktop | ✅ | Development workstation |
| **tyoder-mbp** | macOS (Apple Silicon) | Darwin | ➖ | Triston's TPCC MacBook Pro (work) |
| **Tristons-MacBook-Pro** | macOS (Intel T2) | Darwin | ➖ | Triston's MacBook Pro |

## Deploying from Scratch

### macOS

#### Prerequisites

1. **Install Git** (if not already installed):
   ```bash
   # On a wiped MacBook, git is not installed by default
   # Install Xcode Command Line Tools (includes git)
   xcode-select --install
   # Follow the GUI prompts to complete installation
   ```

2. **Install Nix** (if not already installed):
   ```bash
   # Install Nix
   sh <(curl -L https://nixos.org/nix/install)
   
   # Enable experimental features
   mkdir -p ~/.config/nix
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   ```

3. **Clone the repository**:
   ```bash
   mkdir ~/Projects;cd ~/Projects
   git clone https://github.com/TristonYoder/nix-config.git
   cd nix-config
   ```

#### First-Time Deployment

**For tyoder-mbp:**
```bash
# Enter the repository
cd ~/Projects/nix-config

# Install nix-darwin and apply configuration (first time or after updates)
# This builds the configuration, then activates it with sudo
nix build '.#darwinConfigurations.tyoder-mbp.config.system.build.toplevel' --out-link /tmp/result && \
  sudo /tmp/result/sw/bin/darwin-rebuild switch --flake '.#tyoder-mbp'
```

**For Tristons-MacBook-Pro (Intel T2):**
```bash
# Enter the repository
cd ~/Projects/nix-config

# Install nix-darwin and apply configuration (first time or after updates)
# This builds the configuration, then activates it with sudo
nix build '.#darwinConfigurations."Tristons-MacBook-Pro".config.system.build.toplevel' --out-link /tmp/result && \
  sudo /tmp/result/sw/bin/darwin-rebuild switch --flake '.#Tristons-MacBook-Pro'
```

This will:
1. Install nix-darwin
2. Install and configure Homebrew via nix-homebrew
   - **Apple Silicon (tyoder-mbp):** Includes Rosetta 2 support for x86_64 emulation
   - **Intel (Tristons-MacBook-Pro):** Native x86_64 installation
3. Configure macOS system defaults (keyboard, trackpad, dock, finder, etc.)
4. Install and configure Homebrew casks
5. Install Mac App Store apps (if mas is authenticated)
6. Set up user environment (zsh, git, ssh, etc.)
7. Apply all configuration from this repository

#### Post-Deployment

After first deployment:

1. **Sign in to Mac App Store** (required for mas apps):
   ```bash
   mas signin your-email@apple.com
   ```

2. **Complete Homebrew installations**:
   ```bash
   # Some casks may require manual approval or additional setup
   brew list --cask
   ```

3. **Rebuild to ensure everything is applied**:
   ```bash
   darwin-rebuild switch --flake .
   ```

#### Subsequent Rebuilds

```bash
# From anywhere
darwin-rebuild switch --flake ~/Projects/nix-config

# Or if already in the directory
darwin-rebuild switch --flake .

# Test build without applying
darwin-rebuild build --flake .
```

#### Troubleshooting First Deployment

**If nix-darwin is already installed:**
```bash
# Use darwin-rebuild instead
darwin-rebuild switch --flake .#Tristons-MacBook-Pro
```

**Permission errors:**
```bash
# Grant Full Disk Access to Terminal/iTerm
# System Preferences → Security & Privacy → Privacy → Full Disk Access
```

**Homebrew not found:**
```bash
# Homebrew should be installed automatically by nix-homebrew
# If you still have issues, try rebuilding:
darwin-rebuild switch --flake .
```

**Changes not applied:**
```bash
# Rebuild with verbosity
darwin-rebuild switch --flake . --show-trace

# Or restart the Mac to apply system-level changes
```

#### Switching Between Hosts

If you want to switch from one host configuration to another:

```bash
# For example, switch from Tristons-MacBook-Pro to tyoder-mbp
darwin-rebuild switch --flake .#tyoder-mbp

# Or vice versa
darwin-rebuild switch --flake .#Tristons-MacBook-Pro
```

**Note:** The configurations share most settings via `hosts/darwin-common.nix` and `home/tristonyoder-common.nix`, but differ in:
- Hostname (tyoder-mbp vs Tristons-MacBook-Pro)
- Username (tyoder vs tristonyoder)
- Home directory (/Users/tyoder vs /Users/tristonyoder)

## Quick Start

### NixOS Hosts

```bash
# Auto-detects hostname
sudo nixos-rebuild switch --flake .

# Or specify explicitly
sudo nixos-rebuild switch --flake .#david

# Test before applying
sudo nixos-rebuild test --flake .

# Build without activating
sudo nixos-rebuild build --flake .
```

### macOS

```bash
# First time (install nix-darwin)
nix run nix-darwin -- switch --flake ~/Projects/nix-config

# Subsequent rebuilds
darwin-rebuild switch --flake .

# Test build
darwin-rebuild build --flake .
```

### Common Commands

```bash
# Update flake inputs
nix flake update

# Validate configuration
nix flake check

# Enter dev shell (includes agenix, compose2nix)
nix develop

# View flake outputs
nix flake show
```

### Shell Aliases

The configuration includes helpful aliases:

```bash
rebuild          # NixOS rebuild with auto-detection
rebuild-darwin   # macOS rebuild  
rebuild-home     # Home Manager only
hms              # Quick darwin rebuild shortcut
```

## Configuration

### Enable a Service

Edit your host's `configuration.nix`:

```nix
{
  # Enable with defaults
  modules.services.media.jellyfin.enable = true;
}
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .
```

### Add Packages

Edit `home/<username>.nix`:

```nix
{
  # Nix packages
  home.packages = with pkgs; [
    neofetch
    htop
    ripgrep
  ];
  
  # macOS apps (tyoder.nix only)
  homebrew.casks = [ "firefox" "visual-studio-code" ];
  
  mas.apps = [
    { id = "441258766"; name = "Magnet"; }
  ];
}
```

### Customize Options

```nix
{
  modules.services.media.immich = {
    enable = true;
    domain = "photos.example.com";
    port = 2283;
    mediaLocation = "/data/photos";
  };
}
```

### Check Available Options

```bash
# View service options
nixos-option modules.services.media.immich

# Or browse in the module file
cat modules/services/media/immich.nix
```

### First-Time Service Setup

Some services require initial configuration through their web interface:

#### Nextcloud Setup

After enabling Nextcloud, complete the initial setup at `https://cloud.7andco.dev`:

**Database Configuration:**
- **Database Type:** `postgres`
- **Database Name:** `nextcloud`
- **Database User:** `nextcloud`
- **Database Password:** `<blank>`
- **Database Host:** `/run/postgresql`

**Admin Account:**
- **Username:** `admin`
- **Password:** Use the password from the agenix secret

The data directory will be automatically set to `/data/nextcloud`.

## Architecture

### Profiles

Role-based configurations in `profiles/`:

- **server.nix** - Full-featured server (infrastructure, media, productivity, storage)
- **desktop.nix** - Minimal workstation (KDE Plasma, dev tools)
- **edge.nix** - Lightweight proxy (Caddy, Tailscale, optimized for Pi)
- **darwin.nix** - macOS system configuration

**Usage:**
```nix
{
  imports = [ ../../profiles/server.nix ];
  
  # Override specific settings
  modules.services.media.jellyfin.enable = false;
}
```

See [profiles/README.md](profiles/README.md) for details.

### Modules

Custom NixOS modules organized by category in `modules/`:

**Categories:**
- `hardware/` - GPU, bootloader
- `system/` - Core settings, networking, users, desktop
- `services/infrastructure/` - Caddy, PostgreSQL, Tailscale
- `services/media/` - Jellyfin, Immich, Jellyseerr
- `services/productivity/` - Vaultwarden, n8n, Actual
- `services/storage/` - ZFS, NFS, Samba, Syncthing
- `services/development/` - vscode-server, GitHub Actions

**Benefits:**
- ✅ Single enable flag to activate services
- ✅ Type-safe configuration options
- ✅ Self-documenting through option descriptions
- ✅ Automatic Caddy reverse proxy integration

See [modules/README.md](modules/README.md) for usage and creation guide.

### Hosts

Per-host configurations in `hosts/<hostname>/`:

Each host contains:
- `configuration.nix` - Host-specific settings
- `hardware-configuration.nix` - Hardware config (NixOS only)

Hosts automatically import:
- Common settings (`common/system.nix`, `common/linux.nix` or `common/darwin.nix`)
- Profile (server/desktop/edge/darwin)
- All modules
- Home Manager integration

See [hosts/README.md](hosts/README.md) for adding new hosts.

### Home Manager

User environment configurations in `home/`:

- `common.nix` - Shared settings (git, zsh, ssh, packages)
- `tyoder.nix` - macOS user (Homebrew, Mac App Store, system defaults)
- `tristonyoder.nix` - NixOS user

**Integrated into system rebuilds** - no separate home-manager command needed.

See [home/README.md](home/README.md) for customization.

## Documentation

### Configuration Guides
- [common/README.md](common/README.md) - Common configuration shared across all hosts
- [modules/README.md](modules/README.md) - Module system and available services
- [profiles/README.md](profiles/README.md) - Role-based configuration profiles
- [hosts/README.md](hosts/README.md) - Per-host setup and adding new hosts
- [home/README.md](home/README.md) - User environment configuration

### Operations
- [secrets/README.md](secrets/README.md) - Secret management with agenix
- [docker/README.md](docker/README.md) - Docker Compose services
- [hosts/pits/README.md](hosts/pits/README.md) - Edge server setup

### Resources
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [Home Manager](https://nix-community.github.io/home-manager/)
- [agenix](https://github.com/ryantm/agenix)

## Automated Deployment

Pushing to `main` automatically:

1. ✅ Validates flake syntax
2. ✅ Tests all NixOS configurations in parallel
3. ✅ Deploys to all hosts simultaneously if tests pass
4. ✅ Creates backups before deployment

```bash
git add .
git commit -m "Update configurations"
git push origin main
# GitHub Actions handles the rest!
```

**Manual deployment:**
1. GitHub → Actions → "Deploy NixOS Flake Configuration"
2. Run workflow → Enter hosts: `david,pits` or `all`

**Requirements:**
- Hosts must have `modules.services.development.github-actions.enable = true`
- SSH keys configured for GitHub Actions user

## Configuration Examples

### Full-Featured Server

```nix
{ config, pkgs, lib, ... }:
{
  networking.hostName = "david";
  system.stateVersion = "25.05";
  
  imports = [ ../../profiles/server.nix ];
  
  # Server profile enables all services
  # Customize as needed:
  modules.services.media.immich.domain = "photos.theyoder.family";
  modules.services.productivity.vaultwarden.domain = "vault.theyoder.family";
}
```

### Lightweight Edge Server

```nix
{ config, pkgs, lib, ... }:
{
  networking.hostName = "pits";
  system.stateVersion = "25.05";
  
  imports = [ ../../profiles/edge.nix ];
  
  # Edge profile provides Caddy + Tailscale
  # Optimized for Raspberry Pi
  
  # Add reverse proxies
  services.caddy.virtualHosts."app.example.com" = {
    extraConfig = ''
      reverse_proxy http://david:8080
    '';
  };
}
```

### Desktop Workstation

```nix
{ config, pkgs, lib, ... }:
{
  networking.hostName = "tristons-desk";
  system.stateVersion = "25.05";
  
  imports = [ ../../profiles/desktop.nix ];
  
  # Desktop profile provides KDE + basics
  # Add development tools
  modules.services.development.vscode-server.enable = true;
}
```

### macOS Laptop

```nix
{ config, pkgs, lib, ... }:
{
  networking.hostName = "tyoder-mbp";
  system.stateVersion = 5;
  
  imports = [ ../../profiles/darwin.nix ];
  
  # Darwin profile configures system defaults
  # Apps managed via Home Manager (home/tyoder.nix)
}
```

## Common Tasks

### Update System

```bash
# Update flake inputs
nix flake update

# Rebuild
sudo nixos-rebuild switch --flake .  # NixOS
darwin-rebuild switch --flake .      # macOS
```

### Add a New Host

1. Create `hosts/new-host/configuration.nix`
2. Generate hardware config (NixOS): `nixos-generate-config`
3. Add to `flake.nix` in `nixosConfigurations` or `darwinConfigurations`
4. Choose appropriate profile (server/desktop/edge/darwin)
5. Rebuild: `sudo nixos-rebuild switch --flake .#new-host`

See [hosts/README.md](hosts/README.md) for detailed instructions.

### Add a New Service Module

1. Create module in `modules/services/<category>/`
2. Follow module template pattern
3. Import in category's `default.nix`
4. Enable in host configuration

See [modules/README.md](modules/README.md) for module creation guide.

### Manage Secrets

```bash
cd secrets

# On macOS: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Encrypt new secret
./encrypt-secret.sh -n my-secret.age -e

# View secret
./decrypt-secret.sh cloudflare-api-token.age
```

See [secrets/README.md](secrets/README.md) for complete guide.

## Troubleshooting

### Build Failures

```bash
# Check flake syntax
nix flake check

# Build without applying
sudo nixos-rebuild build --flake .

# Show detailed errors
sudo nixos-rebuild switch --flake . --show-trace
```

### macOS Settings Not Applying

```bash
# Refresh desktop services
killall Dock && killall Finder

# Or log out and back in
```

### Service Not Starting

```bash
# Check if enabled in configuration
grep -r "servicename.enable" hosts/

# View service logs
journalctl -u servicename -f

# Check service status
systemctl status servicename
```

### Rollback Changes

```bash
# NixOS - select previous generation at boot
# Or list generations:
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Switch to previous generation
sudo nix-env --rollback --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

## Security

- **Secrets:** Encrypted with agenix (age encryption)
- **SSH:** Key-based authentication only, root login disabled on edge servers
- **Firewall:** Configured per host with explicit port allowances
- **Updates:** Automated via GitHub Actions with pre-deployment backups
- **Isolation:** Docker services run in isolated containers

## Status

✅ **Multi-host configuration active**  
✅ **4 hosts configured** (david, pits, tristons-desk, tyoder-mbp)  
✅ **Automated CI/CD** (GitHub Actions)  
✅ **40+ custom modules**  
✅ **Home Manager integrated**  
✅ **Secret management** (agenix)  

---

**Last Updated:** October 21, 2025  
**NixOS Version:** 25.05  
**Flake:** Yes ✅  
**Architecture:** Multi-host, multi-platform
