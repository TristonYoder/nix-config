# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a flake-based, multi-host Nix configuration managing NixOS servers, desktops, and macOS machines with integrated Home Manager. The configuration uses a modular architecture with profiles, custom modules, and per-host configurations.

### Managed Hosts

- **david** (NixOS Server) - Full infrastructure stack with media, productivity, storage services
- **pits** (NixOS Edge/Pi) - Lightweight public-facing reverse proxy
- **tristons-desk** (NixOS Desktop) - KDE Plasma workstation
- **tyoder-mbp** (macOS Apple Silicon) - Work MacBook Pro
- **Tristons-MacBook-Pro** (macOS Intel) - Personal MacBook Pro

## Build & Rebuild Commands

### NixOS Hosts

```bash
# Auto-detect hostname and rebuild
sudo nixos-rebuild switch --flake .

# Specify host explicitly
sudo nixos-rebuild switch --flake .#david

# Test configuration without activation
sudo nixos-rebuild test --flake .

# Build without activating
sudo nixos-rebuild build --flake .

# Show detailed error traces
sudo nixos-rebuild switch --flake . --show-trace
```

### macOS (Darwin) Hosts

```bash
# First-time setup (install nix-darwin)
nix build '.#darwinConfigurations.tyoder-mbp.config.system.build.toplevel' --out-link /tmp/result && \
  sudo /tmp/result/sw/bin/darwin-rebuild switch --flake '.#tyoder-mbp'

# Subsequent rebuilds
darwin-rebuild switch --flake .

# For Intel Mac (note the quoted hostname)
darwin-rebuild switch --flake '.#Tristons-MacBook-Pro'

# Test build without applying
darwin-rebuild build --flake .
```

### Validation & Testing

```bash
# Validate flake syntax
nix flake check

# Update flake inputs
nix flake update

# View flake outputs
nix flake show

# Enter development shell (includes agenix, compose2nix)
nix develop
```

### Build Specific Host Configurations

```bash
# Build NixOS host toplevel
nix build '.#nixosConfigurations.david.config.system.build.toplevel'

# Build Darwin host toplevel
nix build '.#darwinConfigurations.tyoder-mbp.config.system.build.toplevel'
```

## Architecture

### Directory Structure

```
.
├── flake.nix                 # Entrypoint defining all host configurations
├── common/                   # Shared system-level configurations
│   ├── system.nix           # Base settings for all hosts
│   ├── linux.nix            # NixOS-specific settings
│   └── darwin.nix           # macOS-specific settings
├── profiles/                 # Role-based configuration sets
│   ├── server.nix           # Full-featured server profile
│   ├── desktop.nix          # KDE Plasma desktop workstation
│   ├── edge.nix             # Lightweight reverse proxy (Pi)
│   └── darwin.nix           # macOS system defaults
├── modules/                  # Custom NixOS modules (service definitions)
│   ├── hardware/            # GPU, bootloader configs
│   ├── system/              # Core settings, networking, users, desktop
│   └── services/
│       ├── infrastructure/  # Caddy, PostgreSQL, Tailscale
│       ├── media/           # Jellyfin, Immich, Jellyseerr
│       ├── productivity/    # Vaultwarden, n8n, Actual
│       ├── storage/         # ZFS, NFS, Samba, Syncthing
│       ├── development/     # vscode-server, GitHub Actions
│       └── communication/   # Matrix, Pixelfed, bridges
├── hosts/                   # Per-host specific configurations
│   └── <hostname>/
│       ├── configuration.nix
│       └── hardware-configuration.nix (NixOS only)
├── home/                    # Home Manager user configurations
│   ├── common.nix          # Shared user settings
│   ├── tristonyoder.nix    # NixOS user
│   └── tyoder.nix          # macOS user (with Homebrew/mas)
├── docker/                  # Docker Compose service definitions
└── secrets/                 # Encrypted secrets (agenix)
```

### Module System Pattern

All custom modules follow this structure:

```nix
# modules/services/category/servicename.nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.category.servicename;
in
{
  options.modules.services.category.servicename = {
    enable = mkEnableOption "Service Description";
    domain = mkOption { type = types.str; default = "service.domain.com"; };
    port = mkOption { type = types.int; default = 8080; };
  };

  config = mkIf cfg.enable {
    # Service configuration
    services.servicename.enable = true;

    # Optional: Auto Caddy reverse proxy integration
    services.caddy.virtualHosts.${cfg.domain} =
      mkIf config.modules.services.infrastructure.caddy.enable {
        extraConfig = ''reverse_proxy http://localhost:${toString cfg.port}'';
      };
  };
}
```

Enable modules in host configurations:

```nix
# hosts/hostname/configuration.nix
{
  modules.services.media.jellyfin.enable = true;

  # With custom options
  modules.services.media.immich = {
    enable = true;
    domain = "photos.example.com";
    port = 2283;
  };
}
```

### Configuration Hierarchy

Hosts import configurations in this order:

1. `common/system.nix` - Base settings for all hosts
2. `common/linux.nix` OR `common/darwin.nix` - Platform-specific
3. `profiles/*.nix` - Role-based configuration (server/desktop/edge/darwin)
4. `modules/` - All custom modules auto-imported
5. `hosts/<hostname>/configuration.nix` - Host-specific overrides
6. Home Manager integration

Later imports can override earlier ones using `lib.mkForce`.

## Development Workflow

### Feature Branch Process

For non-trivial changes, use feature branches:

```bash
# Create feature branch with descriptive name
git checkout -b category/brief-description

# Examples:
git checkout -b feat/add-service-name
git checkout -b fix/service-startup-issue
git checkout -b optimize/homebrew-rebuild-performance

# Make changes and commit
git add .
git commit -m "category: brief description

Additional context for troubleshooting."

# Merge to main when ready
git checkout main
git merge category/brief-description
git push
```

Commit message conventions:
- `feat:` - New features
- `fix:` - Bug fixes
- `perf:` - Performance improvements
- `refactor:` - Code restructuring
- `docs:` - Documentation updates

Keep messages minimal but helpful for future troubleshooting.

### Creating a New Service Module

1. Create module file: `modules/services/<category>/<servicename>.nix`
2. Follow the module template pattern (see Architecture section)
3. Import in category's `default.nix`:
   ```nix
   {
     imports = [
       ./servicename.nix
       # ... other modules
     ];
   }
   ```
4. Enable in host configuration: `modules.services.category.servicename.enable = true;`
5. Test: `nix flake check && sudo nixos-rebuild test --flake .`

### Adding a New Host

1. Create `hosts/<hostname>/configuration.nix`
2. For NixOS: Generate `hardware-configuration.nix` with `nixos-generate-config`
3. Add host to `flake.nix` in `nixosConfigurations` or `darwinConfigurations`
4. Choose appropriate profile import (server/desktop/edge/darwin)
5. Rebuild: `sudo nixos-rebuild switch --flake .#hostname`

### Managing Secrets (agenix)

Secrets are encrypted with SSH public keys using agenix.

```bash
cd secrets

# On macOS: Add nix to PATH
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Encrypt new secret (recommended - uses helper script)
./encrypt-secret.sh -n my-secret.age -e

# Decrypt/view secret
./decrypt-secret.sh cloudflare-api-token.age

# CRITICAL: Always use ssh-ed25519 keys, NOT X25519
# Use -R flag with age, not -r when encrypting manually
```

Declare secrets in `modules/secrets.nix`:

```nix
age.secrets.my-secret = {
  file = ../secrets/my-secret.age;
  owner = "servicename";
  group = "servicename";
};
```

Reference in modules: `config.age.secrets.my-secret.path`

### Docker Compose Services

Docker services are organized in `docker/` by category. Changes to Docker services:

1. Edit service definition in `docker/<category>/<service>.nix`
2. Use `compose2nix` if converting from docker-compose.yml
3. Rebuild system (Docker services are part of NixOS configuration)

## Important Conventions

### Profile Usage

- **Profiles** (`profiles/*.nix`) enable sets of services for specific roles
- **Don't modify profiles** unless you want to affect multiple hosts
- **Override in host configs** for host-specific customization:
  ```nix
  {
    imports = [ ../../profiles/server.nix ];
    # Disable specific service from profile
    modules.services.media.jellyseerr.enable = false;
  }
  ```

### Home Manager Integration

- Home Manager is integrated into system rebuilds - no separate `home-manager` command needed
- NixOS uses `home-manager.nixosModules.home-manager`
- Darwin uses `home-manager-unstable.darwinModules.home-manager`
- User configs in `home/` are imported via `flake.nix`
- Changes to Home Manager configs require full system rebuild

### macOS Homebrew/MAS Performance

The Homebrew and Mac App Store (mas) modules use batch-checking for optimal rebuild performance:

- `home/modules/homebrew.nix` - Fetches `brew list --formula` and `brew list --cask` once, then checks all packages against cached list
- `home/modules/mas.nix` - Fetches `mas list` once, then checks all apps against cached list

This reduces darwin-rebuild from 50+ individual command invocations to just 3 total (brew list --formula, brew list --cask, mas list), significantly improving rebuild speed. Output is silent when all packages are already installed.

### Version Consistency

- NixOS hosts use `nixpkgs` (25.05 stable)
- Darwin hosts use `nixpkgs-unstable` (nix-darwin requires unstable)
- Home Manager versions match: NixOS uses stable, Darwin uses unstable
- When updating inputs, test on both platforms

### Automated Deployment

- GitHub Actions automatically tests and deploys on push to `main`
- Requires hosts to have `modules.services.development.github-actions.enable = true`
- Manual workflow dispatch available for selective host deployment

## Common Troubleshooting

### Build Failures

```bash
# Check syntax and evaluate
nix flake check

# Build without applying to test
sudo nixos-rebuild build --flake .

# Show detailed error traces
sudo nixos-rebuild switch --flake . --show-trace
```

### Service Not Starting

```bash
# Verify module enabled
grep -r "servicename.enable" hosts/

# Check service status
systemctl status servicename

# View logs
journalctl -u servicename -f
```

### macOS Settings Not Applying

```bash
# Refresh desktop services
killall Dock && killall Finder

# Some settings require logout/login
```

### Port Conflicts

```bash
# Check port usage
sudo ss -tulpn | grep PORT

# Override port in module options
modules.services.category.servicename.port = 8081;
```

## References

Key documentation files in this repository:

- `README.md` - Comprehensive repository overview and quick start
- `modules/README.md` - Module system usage and creation guide
- `profiles/README.md` - Role-based configuration details
- `hosts/README.md` - Adding and managing hosts
- `home/README.md` - User environment customization
- `secrets/README.md` - Secret management with agenix
- `docker/README.md` - Docker Compose service management
