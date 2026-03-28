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

## Security — This Repo Is Public

**CRITICAL: This repository is public on GitHub. Never write secrets, credentials, tokens, passwords, or any sensitive values anywhere in the repo — including CLAUDE.md, comments, commit messages, or documentation — unless they are encrypted via the `secrets/` agenix system.**

If you encounter a secret value during a session (e.g. a user pastes a token or password), do NOT write it to any file in the repo. Direct the user to encrypt it with `encrypt-secret.sh` instead.

Acceptable locations for secret material:
- `secrets/*.age` — encrypted with agenix (SSH public keys), safe to commit
- Runtime paths like `/run/agenix/<secret>` — decrypted on-host only, never in the repo

## Knowledge Management

CLAUDE.md is the primary knowledge store for this repo. It is committed to git and automatically synced across all machines via `git pull`.

**What belongs here:** Architecture principles, design decisions, troubleshooting playbooks, and workflow rules — anything stable and worth carrying into every session. Never include secret values (see Security section above).

**What belongs in `~/.claude/` memory:** In-progress work, open design questions, and transient session context. When something in memory stabilizes (a bug fix pattern, a finalized design), promote it to CLAUDE.md and delete the memory file. Never store secret values in memory files either.

**Cross-machine sync for in-progress memory:**
```bash
# Sync from local to david (or reverse)
rsync -av ~/.claude/projects/-Users-tyoder-Projects-nix-config/memory/ \
  tristonyoder@david:~/.claude/projects/-data-tristonyoder-home-Projects-nix-config/memory/
```

Run this when switching machines if there's active in-progress memory that hasn't been promoted yet.

## Build & Rebuild Commands

Use the `rebuild` shorthand — it auto-detects the host and runs the appropriate command:
```bash
rebuild
```

**Always commit changes before rebuilding.** This is a flake-based repo — the build reads from the git tree, not the working directory. Uncommitted changes are invisible to the builder.

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

**IMPORTANT**: Detect which host you're running on to adjust build/test behavior:

**Current host detection**:
```bash
hostname  # Returns: tyoder-mbp, Tristons-MacBook-Pro, david, tristons-desk, or pits
```

**Testing policy by host**:

- **On macOS hosts** (tyoder-mbp, Tristons-MacBook-Pro):
  - Do NOT run `nix flake check` or NixOS builds locally - too resource-intensive
  - SSH to target NixOS host for testing instead
  - Can safely run: `nix flake update`, `nix flake show`, `darwin-rebuild build`

- **On NixOS hosts** (david, tristons-desk, pits):
  - Can run builds and tests directly on the local host
  - No need to SSH elsewhere

**Remote testing from macOS** (when NOT on target host):
```bash
# Test on david (most common - server with all services)
ssh github-actions@david "cd /home/github-actions/nix-config && git fetch origin && git checkout <branch> && git pull origin <branch> && sudo nixos-rebuild dry-run --flake .#david"

# Or build without activation
ssh github-actions@david "cd /home/github-actions/nix-config && sudo nixos-rebuild build --flake .#david"
```

**Local testing on NixOS** (when already on target host):
```bash
# Dry-run rebuild
sudo nixos-rebuild dry-run --flake .

# Build without activation
sudo nixos-rebuild build --flake .

# Test without activation
sudo nixos-rebuild test --flake .
```

**Safe to run on any host**:
```bash
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

### Agnostic Module Design

Service modules declare their requirements through typed options. Provider modules consume those declarations and implement them. No service module should directly configure Caddy, nginx, ZFS, PostgreSQL, etc.

**Why:** Swapping a provider (e.g. reverse proxy, DNS, storage) requires only a new consumer module — zero changes to the service modules that declare their needs. The vHosts module demonstrated this: 25+ service modules declare a domain/port, and Caddy + Technitium each consume that without the services knowing.

**Rule:** When building a service module, ask "could this declaration be consumed by a different provider?" If yes, it belongs in the agnostic options layer. Provider-specific escape hatches (like `extraConfig`) are acceptable but should be treated as non-portable.

**Established abstractions:**
- `modules.services.vHosts.hosts` — reverse proxy + DNS (consumed by Caddy, Technitium)
- `modules.services.appData` — service data directories (consumed by plain fs or ZFS provider)

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

**IMPORTANT**: Keep commit messages, PR descriptions, and documentation simple and to the point. Focus on clarity for future troubleshooting. Do NOT add:
- Attribution footers (e.g., "🤖 Generated with Claude Code")
- Unnecessary boilerplate or fluff
- Excessive formatting or emojis

Write concisely with technical accuracy.

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

**This repo is public. All secrets must be encrypted before committing. Never commit plaintext credentials, tokens, or passwords — not even temporarily.**

Secrets are encrypted with SSH public keys using agenix.

**CRITICAL**: ALWAYS use `encrypt-secret.sh` for encrypting/re-encrypting secrets. DO NOT encrypt manually with age commands. Manual encryption often results in X25519 format which breaks agenix decryption on hosts.

```bash
cd secrets

# On macOS: Add nix to PATH
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Encrypt new secret (REQUIRED - always use this script)
./encrypt-secret.sh -n my-secret.age -e

# Re-encrypt existing secret for new hosts
# 1. Decrypt first
./decrypt-secret.sh my-secret.age > /tmp/plain.txt
# 2. Re-encrypt with script
./encrypt-secret.sh -n my-secret.age -f /tmp/plain.txt
# 3. Clean up
rm /tmp/plain.txt

# Decrypt/view secret
./decrypt-secret.sh cloudflare-api-token.age

# Verify secret has correct format (should show ssh-ed25519, NOT X25519)
./encrypt-secret.sh -v my-secret.age
```

**Why the script is required**:
- Automatically fetches SSH host keys from servers (ensures correct recipients)
- Uses `-R` flag for SSH public key encryption (not age keys)
- Verifies output has `ssh-ed25519` recipients (not X25519)
- X25519-encrypted secrets cause "no identity matched" errors on hosts

Declare secrets in `modules/secrets.nix`:

```nix
age.secrets.my-secret = {
  file = ../secrets/my-secret.age;
  owner = "servicename";
  group = "servicename";
};
```

Reference in modules: `config.age.secrets.my-secret.path`

### Debugging GitHub Actions Failures

```bash
# List recent runs to find the failed run ID
gh run list --branch main --limit 5

# Fetch failed job logs
gh run view <run-id> --log-failed

# If output is too large it saves to a temp file — grep it directly
grep -n "error\|Error\|failed\|Failed" <saved-log-file> | tail -60
```

The CI matrix runs jobs for each host (e.g. `test-configurations (david, david)`). The rsync file listing is verbose — skip past it to find the actual `nixos-rebuild dry-run` error.

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

### SDDM Blinking Cursor (No Login Screen)
**Host:** david — Plasma 6 + NVIDIA

SDDM defaults to `DisplayServer=wayland`. The NVIDIA DRM driver rejects the `video=1920x1080` kernel param set by `modules/hardware/display-resolution.nix`, causing `kwin_wayland` to exit after ~1 second. SDDM never retries.

**Quick fix:** `sudo systemctl restart display-manager`

**Permanent fix options (not yet applied):**
- Disable SDDM Wayland: `services.displayManager.sddm.wayland.enable = false;`
- Remove the `video=` kernel param from `display-resolution.nix` — NVIDIA DRM doesn't support user-defined modes (only useful for simpledrm/efifb)

**Diagnostics:**
```bash
systemctl status display-manager
journalctl --grep="sddm|kwin"
journalctl --grep="nvidia.*drm"
ls /tmp/.X11-unix/   # empty = no display running
```

### Qt Apps Crash on Plasma 6 Wayland (SIGABRT / exit 134)
**Host:** david — Plasma 6 Wayland + NVIDIA

Exit code 134 (SIGABRT) at `init_platform` in libQt6Gui means Qt can't find a platform plugin. The nixpkgs dolphin-emu wrapper hardcodes `--set QT_QPA_PLATFORM xcb`. On Wayland, XWayland starts on-demand and `DISPLAY` is unset, so Qt aborts trying xcb.

**Fix applied:** `modules/system/desktop.nix` — `xwayland-init` systemd user service forces KWin to start XWayland eagerly at login. This fixes all Qt xcb apps at once. `environment.sessionVariables` cannot override binary wrappers that use `--set`.

**Diagnostics:**
```bash
coredumpctl list
# Journal: look for init_platform in Qt stack trace
cat $(which <app>)   # check for QT_QPA_PLATFORM hardcode
loginctl show-session <id>   # Type=wayland = no native X11
```

### Headscale Preauthkeys Missing `--tags` Breaks CI SSH
**Context:** GitHub Actions CI runners joining the Tailscale mesh via headscale

Without `--tags tag:github-actions`, preauthkeys produce untagged nodes. The headscale SSH ACL requires `tag:github-actions` as source, so "failed to evaluate SSH policy" is returned (policy can't match — not an explicit deny).

**Always create preauthkeys with:**
```bash
sudo headscale preauthkeys create --user github-actions --reusable --ephemeral --expiration 168h --tags tag:github-actions
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
