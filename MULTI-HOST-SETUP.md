# Multi-Host Configuration Guide

This repository now supports multiple hosts across NixOS and macOS (Darwin) platforms with integrated Home Manager.

## 🏗️ Directory Structure

```
.
├── flake.nix                   # Main flake with all host configurations
├── common.nix                  # Shared settings across all hosts
│
├── profiles/                   # Role-based configuration profiles
│   ├── server.nix              # Server role (all services enabled)
│   ├── desktop.nix             # Desktop role (minimal, workstation-focused)
│   └── darwin.nix              # macOS role (system preferences)
│
├── hosts/                      # Per-host configurations
│   ├── david/                  # Main server
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   ├── tristons-desk/          # Desktop workstation
│   │   ├── configuration.nix
│   │   └── hardware-configuration.nix
│   └── tyoder-mbp/             # macOS MacBook Pro
│       └── configuration.nix
│
├── home/                       # Home Manager configurations
│   ├── common.nix              # Shared user settings (git, zsh, etc.)
│   ├── tyoder.nix              # macOS user (with homebrew/mas)
│   ├── tristonyoder.nix        # NixOS user
│   ├── p10k.zsh                # Powerlevel10k theme config
│   └── modules/
│       ├── homebrew.nix        # Custom homebrew module
│       └── mas.nix             # Mac App Store module
│
├── modules/                    # System modules (existing)
├── docker/                     # Docker services (existing)
└── secrets/                    # Encrypted secrets (existing)
```

## 🖥️ Configured Hosts

### NixOS Hosts

#### `david` (x86_64-linux)
- **Role**: Server
- **Profile**: `profiles/server.nix`
- **Services**: All infrastructure, media, productivity, and storage services
- **User**: tristonyoder
- **Location**: `hosts/david/`

#### `tristons-desk` (x86_64-linux)
- **Role**: Desktop Workstation
- **Profile**: `profiles/desktop.nix`
- **Services**: Minimal (core, desktop, development tools)
- **User**: tristonyoder
- **Location**: `hosts/tristons-desk/`

### macOS (Darwin) Hosts

#### `tyoder-mbp` (aarch64-darwin)
- **Role**: macOS Laptop
- **Profile**: `profiles/darwin.nix`
- **Services**: Home Manager with Homebrew and Mac App Store integration
- **User**: tyoder
- **Location**: `hosts/tyoder-mbp/`

## 🚀 Usage

### Auto-Detection (Recommended)

Each host automatically detects its hostname and uses the matching configuration:

```bash
# On any NixOS machine (david or tristons-desk):
sudo nixos-rebuild switch --flake .

# On macOS (tyoder-mbp):
darwin-rebuild switch --flake .
```

### Explicit Host Selection

You can also explicitly specify the host:

```bash
# NixOS
sudo nixos-rebuild switch --flake .#david
sudo nixos-rebuild switch --flake .#tristons-desk

# macOS
darwin-rebuild switch --flake .#tyoder-mbp
```

### Shell Aliases

Convenient aliases are configured in Home Manager:

```bash
rebuild          # NixOS rebuild (auto-detects host)
rebuild-darwin   # macOS rebuild
rebuild-home     # Home Manager only
```

## 📝 Configuration Details

### Common Configuration (`common.nix`)

Shared across all hosts:
- Nix settings (flakes, auto-gc, trusted users)
- Locale and timezone (with per-host override capability)
- Common system packages
- Security settings

### Profiles

**Server Profile** (`profiles/server.nix`):
- All infrastructure services (Caddy, PostgreSQL, Tailscale, etc.)
- Media services (Jellyfin, Immich, etc.)
- Productivity services (Vaultwarden, n8n, Actual)
- Storage services (ZFS, NFS, Samba, Syncthing)
- Development tools

**Desktop Profile** (`profiles/desktop.nix`):
- Core system modules
- Desktop environment (KDE Plasma)
- Development tools (vscode-server)
- Tailscale for VPN access
- Minimal service footprint

**Darwin Profile** (`profiles/darwin.nix`):
- macOS system configuration
- Touch ID for sudo
- System fonts
- Integration with Home Manager

### Home Manager

**Common** (`home/common.nix`):
- Git configuration
- Zsh with Oh My Zsh
- Powerlevel10k theme
- SSH configuration
- Shared packages (git, gh, compose2nix, etc.)
- Shell aliases

**macOS User** (`home/tyoder.nix`):
- macOS system defaults (Dock, Finder, etc.)
- Homebrew cask management
- Mac App Store app management
- macOS-specific activation scripts

**NixOS User** (`home/tristonyoder.nix`):
- Linux-specific configuration
- Extends common configuration

## 🔧 Adding a New Host

1. **Create host directory**:
   ```bash
   mkdir -p hosts/new-hostname
   ```

2. **Create configuration**:
   ```nix
   # hosts/new-hostname/configuration.nix
   { config, pkgs, lib, ... }:
   {
     networking.hostName = "new-hostname";
     system.stateVersion = "25.05";
     # Import appropriate profile or customize
   }
   ```

3. **For NixOS hosts**, generate hardware config on target machine:
   ```bash
   sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
   ```

4. **Add to flake.nix**:
   ```nix
   nixosConfigurations.new-hostname = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     modules = [
       ./common.nix
       ./profiles/desktop.nix  # or server.nix
       ./hosts/new-hostname/configuration.nix
       ./hosts/new-hostname/hardware-configuration.nix
       ./modules
       # ... home-manager, etc.
     ];
   };
   ```

5. **Build and switch**:
   ```bash
   sudo nixos-rebuild switch --flake .
   ```

## 🔐 Secrets Management

Secrets are managed with agenix and stored in the `secrets/` directory. See `secrets/README.md` for details.

## 📦 Updating

### Update flake inputs:
```bash
nix flake update
```

### Update specific input:
```bash
nix flake lock --update-input nixpkgs
```

### Check what will change:
```bash
nix flake check
nixos-rebuild build --flake .  # or darwin-rebuild build
```

## 🛠️ Development

### Development shells:
```bash
# Default shell (includes agenix, git, gh, compose2nix)
nix develop

# Bitcoin development shell
nix develop .#bitcoin
```

## 📚 Additional Documentation

- [Modular Structure Guide](MODULAR-STRUCTURE.md) - Details on the module system
- [Refactoring Summary](REFACTORING-SUMMARY.md) - History of configuration changes
- [Secrets Management](secrets/README.md) - How to manage encrypted secrets
- [Flake Setup](README-FLAKE.md) - Original flake documentation
- [GitHub Actions](README-GitHub-Actions.md) - CI/CD setup

## 🎯 Key Features

✅ **Multi-Platform**: NixOS and macOS from single repository  
✅ **Auto-Detection**: Hostname-based configuration selection  
✅ **Home Manager**: Integrated user environment management  
✅ **Profile-Based**: Role-based configuration inheritance  
✅ **Modular**: Easy to enable/disable services per host  
✅ **Secrets**: Encrypted secret management with agenix  
✅ **Type-Safe**: NixOS option system with validation  

## 🚨 Important Notes

### First-Time Setup

**On macOS (tyoder-mbp)**:
1. Install nix-darwin: Follow instructions at https://github.com/LnL7/nix-darwin
2. Clone this repository to `~/Projects/david-nixos`
3. Run: `darwin-rebuild switch --flake ~/Projects/david-nixos`

**On NixOS hosts**:
1. Generate hardware config: `sudo nixos-generate-config`
2. Copy `hardware-configuration.nix` to `hosts/HOSTNAME/`
3. Customize `hosts/HOSTNAME/configuration.nix`
4. Run: `sudo nixos-rebuild switch --flake .`

### p10k.zsh

The Powerlevel10k configuration (`home/p10k.zsh`) may need to be customized. If it doesn't exist, run `p10k configure` after first Home Manager activation.

### macOS System Changes

Some macOS system defaults require logout/restart to take effect. After first run on macOS:
1. Log out and back in
2. Some settings may require: `killall Dock && killall Finder`

## 🤝 Contributing

When adding new services or modules, follow the existing patterns:
- Put reusable modules in `modules/`
- Use profiles for role-based configuration
- Keep host-specific settings minimal
- Document any host-specific overrides

