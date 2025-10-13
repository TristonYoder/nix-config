# Multi-Host NixOS & Darwin Configuration

> A unified, flake-based configuration managing NixOS servers, desktops, and macOS machines with integrated Home Manager and automated CI/CD.

[![NixOS](https://img.shields.io/badge/NixOS-25.05-blue.svg)](https://nixos.org)
[![Flakes](https://img.shields.io/badge/Nix-Flakes-green.svg)](https://nixos.wiki/wiki/Flakes)
[![macOS](https://img.shields.io/badge/macOS-nix--darwin-blueviolet.svg)](https://github.com/LnL7/nix-darwin)

## ✨ Features

- **🖥️ Multi-Platform** - NixOS and macOS from a single repository
- **🚀 Automated Deployment** - GitHub Actions CI/CD for all hosts
- **🔄 Parallel Updates** - Deploy to all machines simultaneously
- **🏠 Home Manager** - Unified user environment across all platforms
- **📦 Modular Services** - 40+ custom modules with type-safe options
- **🔐 Secret Management** - Encrypted secrets with agenix
- **🎯 Profile-Based** - Role-specific configurations (server/desktop/edge/darwin)
- **⚡ Auto-Detection** - Hostname-based configuration selection

## 📊 Managed Hosts

| Host | Type | Profile | Auto-Deploy | Services |
|------|------|---------|-------------|----------|
| **david** | NixOS Server | Server | ✅ | Infrastructure, Media, Productivity, Storage |
| **pits** | NixOS Edge (Pi) | Edge | ✅ | Caddy, Tailscale, minimal footprint |
| **tristons-desk** | NixOS Desktop | Desktop | ✅ | KDE Plasma, development tools |
| **tyoder-mbp** | macOS (M1) | Darwin | ➖ | Homebrew, Mac App Store, dev tools |

## 🚀 Quick Start

### NixOS Hosts

```bash
# Auto-detects hostname
sudo nixos-rebuild switch --flake .

# Or specify host explicitly
sudo nixos-rebuild switch --flake .#david
```

### macOS

```bash
# First time (install nix-darwin)
nix run nix-darwin -- switch --flake ~/Projects/david-nixos

# Subsequent rebuilds
darwin-rebuild switch --flake .
```

## 📁 Repository Structure

```
.
├── flake.nix              # Main flake with all host configurations
├── common.nix             # Shared settings across all hosts
│
├── hosts/                 # Per-host configurations
│   ├── david/             # Main server
│   ├── pits/              # Edge server (Raspberry Pi)
│   ├── tristons-desk/     # Desktop workstation
│   └── tyoder-mbp/        # macOS laptop
│
├── profiles/              # Role-based configurations
│   ├── server.nix         # Full server stack
│   ├── desktop.nix        # Minimal desktop
│   ├── edge.nix           # Optimized for low resources
│   └── darwin.nix         # macOS system configuration
│
├── modules/               # Custom NixOS modules
│   ├── hardware/          # GPU, bootloader
│   ├── system/            # Core, networking, users, desktop
│   └── services/          # Infrastructure, media, productivity, storage, development
│
├── home/                  # Home Manager configurations
│   ├── common.nix         # Shared user settings
│   ├── tyoder.nix         # macOS user (Homebrew, MAS)
│   └── tristonyoder.nix   # NixOS user
│
├── docker/                # Docker Compose services (via compose2nix)
├── secrets/               # Encrypted secrets (agenix)
└── docs/                  # Detailed documentation
```

## 🛠️ Common Tasks

### Update System

```bash
# Update flake inputs
nix flake update

# Rebuild system
sudo nixos-rebuild switch --flake .  # NixOS
darwin-rebuild switch --flake .      # macOS
```

### Enable a Service

Edit `hosts/<hostname>/configuration.nix`:

```nix
{
  # Enable with defaults
  modules.services.media.jellyfin.enable = true;
  
  # Or customize
  modules.services.media.immich = {
    enable = true;
    domain = "photos.example.com";
    port = 2283;
  };
}
```

### Add Packages

Edit `home/<username>.nix`:

```nix
{
  home.packages = with pkgs; [
    neofetch
    htop
  ];
  
  # macOS apps
  homebrew.casks = [ "firefox" ];
  mas.apps = [{ id = "441258766"; name = "Magnet"; }];
}
```

### Check Configuration

```bash
# Validate flake
nix flake check

# Test without applying
sudo nixos-rebuild test --flake .
darwin-rebuild build --flake .
```

### Development Shells

```bash
# Enter development shell (includes agenix, git, gh, compose2nix)
nix develop

# Bitcoin development shell
nix develop .#bitcoin
```

## 🤖 Automated Deployment

Pushing to the `main` branch automatically:

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

**Manual deployment to specific hosts:**

1. GitHub → Actions → "Deploy NixOS Flake Configuration"
2. Run workflow → Enter hosts: `david,pits` or `all`

See [.github/workflows/README.md](.github/workflows/README.md) for complete CI/CD guide.

## 📚 Documentation

### Getting Started
- **[QUICKSTART.md](QUICKSTART.md)** - Essential commands and quick reference
- **[Hosts](hosts/README.md)** - Complete multi-host setup guide

### Configuration
- **[Modules](modules/README.md)** - Module system, available services, and usage
- **[Profiles](profiles/README.md)** - Role-based configuration profiles  
- **[Home Manager](home/README.md)** - User environment configuration
- **[Docker Services](docker/README.md)** - Container management

### Automation & Security
- **[GitHub Actions](.github/workflows/README.md)** - Automated CI/CD testing and deployment
- **[Secret Management](secrets/README.md)** - agenix encrypted secrets

### Host-Specific Guides
- **[pits (Edge Server)](hosts/pits/README.md)** - Setup and configuration
- **[pits Installation](hosts/pits/INSTALLATION.md)** - Detailed installation guide  
- **[pits Bootstrap](hosts/pits/BOOTSTRAP.md)** - Quick bootstrap process

## 💡 Configuration Examples

### NixOS Server (david)

Full-featured server with all services:

```nix
{
  imports = [ ../../profiles/server.nix ];
  
  networking.hostName = "david";
  
  # All services enabled by server profile
  # Customize as needed:
  modules.services.media.immich.domain = "photos.theyoder.family";
}
```

### Edge Server (pits)

Lightweight public-facing proxy:

```nix
{
  imports = [ ../../profiles/edge.nix ];
  
  networking.hostName = "pits";
  
  # Optimized for Raspberry Pi
  # Caddy + Tailscale enabled by edge profile
}
```

### Desktop (tristons-desk)

Minimal workstation setup:

```nix
{
  imports = [ ../../profiles/desktop.nix ];
  
  networking.hostName = "tristons-desk";
  
  # KDE Plasma + basic tools enabled by desktop profile
  # Add extra services as needed
  modules.services.development.vscode-server.enable = true;
}
```

### macOS (tyoder-mbp)

Native macOS configuration:

```nix
{
  imports = [ ../../profiles/darwin.nix ];
  
  networking.hostName = "tyoder-mbp";
  
  # System defaults configured by darwin profile
  # Apps managed via Home Manager (homebrew/MAS)
}
```

## 🔐 Security

- **Secrets:** Encrypted with agenix (age encryption)
- **SSH:** Key-based authentication only
- **Firewall:** Configured per host
- **Updates:** Automated via GitHub Actions
- **Backups:** Created before each deployment

## 🎯 Module System Benefits

| Before | After |
|--------|-------|
| 214-line monolithic config | ~100 lines of enable flags |
| 386-line apps.nix | ~50 lines per service module |
| Hard to find services | Navigate by category |
| Comment/uncomment blocks | Single enable toggle |
| Basic validation | Full type-safe options |

## 🔧 Adding Components

### Add a New Host

1. Create `hosts/new-host/configuration.nix`
2. Generate hardware config (NixOS): `nixos-generate-config`
3. Add to `flake.nix` in `nixosConfigurations` or `darwinConfigurations`
4. Choose appropriate profile
5. Rebuild: `sudo nixos-rebuild switch --flake .`

See [hosts/README.md](hosts/README.md) for detailed instructions.

### Add a New Service Module

1. Create module in `modules/services/<category>/`
2. Follow module template pattern
3. Import in category's `default.nix`
4. Enable in host configuration

See [modules/README.md](modules/README.md) for module creation guide.

## 📦 What's Included

<details>
<summary><b>NixOS Server (david)</b> - Full infrastructure stack</summary>

**Infrastructure:**
- Caddy reverse proxy with Cloudflare DNS
- PostgreSQL database
- Tailscale VPN
- Technitium DNS server

**Media:**
- Jellyfin media server with hardware transcoding
- Immich photo management with public sharing
- Jellyseerr media request management
- Sunshine game streaming

**Productivity:**
- Vaultwarden password manager
- n8n workflow automation
- Actual budget application

**Storage:**
- ZFS filesystem
- NFS server
- Samba/CIFS file sharing
- Syncthing synchronization

**Development:**
- vscode-server for remote development
- GitHub Actions runner integration
</details>

<details>
<summary><b>NixOS Edge (pits)</b> - Optimized lightweight proxy</summary>

- Caddy reverse proxy
- Tailscale VPN
- vscode-server
- Aggressive resource optimizations
- Designed for Raspberry Pi
</details>

<details>
<summary><b>NixOS Desktop (tristons-desk)</b> - Minimal workstation</summary>

- KDE Plasma 6 desktop
- Development tools
- Tailscale VPN
- vscode-server
- Minimal service footprint
</details>

<details>
<summary><b>macOS (tyoder-mbp)</b> - Native macOS experience</summary>

- Declarative system preferences
- Homebrew package management
- Mac App Store integration
- Zsh with Oh My Zsh & Powerlevel10k
- Touch ID for sudo
- Git, development tools
</details>

## 🤝 Contributing

This is a personal configuration, but feel free to use it as reference!

When making changes:
1. Test on feature branch first
2. Validate: `nix flake check`
3. Test build: `nixos-rebuild build --flake .`
4. Document significant changes
5. Update relevant README files

## 📞 Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [Home Manager](https://nix-community.github.io/home-manager/)
- [agenix](https://github.com/ryantm/agenix)

## 📊 Status

✅ **Multi-host configuration active**  
✅ **4 hosts configured** (david, pits, tristons-desk, tyoder-mbp)  
✅ **Automated CI/CD** (GitHub Actions)  
✅ **40+ custom modules**  
✅ **Home Manager integrated**  
✅ **Secret management** (agenix)  
✅ **Documentation complete**  

---

**Last Updated:** October 13, 2025  
**NixOS Version:** 25.05+  
**Flake:** Yes ✅  
**Architecture:** Multi-host, multi-platform
