# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a flake-based, multi-host Nix configuration managing NixOS servers, desktops, and macOS machines with integrated Home Manager. The configuration uses a modular architecture with profiles, custom modules, and per-host configurations.

### Managed Hosts

- **david** (NixOS Server) - Full infrastructure stack with media, productivity, storage services. Primarily a server, but also used as a workstation at times — hence the multi-profile setup (server profile plus desktop-capable pieces). Don't assume it's headless; desktop-oriented packages (e.g. `mainUser.packages` defaults like `bitwarden-desktop`) are intentionally present, not stray bloat.
- **pits** (NixOS Edge/Pi) - Lightweight public-facing reverse proxy
- **tristons-workstation** (NixOS Desktop) - KDE Plasma workstation. RTX 4080 (open NVIDIA kernel modules), btrfs root (`@`, `@nix`, `@snapshots` subvolumes), `/home` symlinked to NFS-mounted `/data` on david (`useDataDrive`). **Always has a 10Gb fiber backhaul to david over the Core Services VLAN** — this is a permanent network characteristic of this host, not a one-off; treat NFS-backed home and any future high-bandwidth dependency on david as safe to assume for this host specifically. Dual-NIC: `enp7s0` carries `10.150.100.0/23` (Core Services, route to david), `eno1` carries `10.150.10.0/24` (User Devices). `network-online.target` may fire on `eno1` before `enp7s0` completes DHCP — see the NFS automount troubleshooting entry before touching boot-time network ordering on this host.
- **tristons-nixbook** (NixOS Laptop) - Workstation profile on a MacBook. NFS-mounts `/data` from david. Key swap (Command↔Control) via keyd for MacBook keyboard layout.
- **tristons-nixbook-pro** (NixOS on T2 MacBook Pro 16,1) - Dual-boot, uses `nixos-hardware.apple-t2`. Custom bootable installer ISOs built from the flake (`tristons-nixbook-pro-installer`, `tristons-nixbook-pro-installer-plasma`).
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

Use the `rebuild` shorthand — it auto-detects the host, fetches from GitHub, and runs the appropriate command:
```bash
rebuild
```

**Always commit AND push before rebuilding.** All hosts now build from `github:TristonYoder/nix-config` — the build fetches the latest pushed commit on `main`. Uncommitted or unpushed changes are invisible to the builder.

**`--refresh` is required** when building from `github:` URLs. Without it, nix may use a locally cached resolution of the flake ref and silently build from a stale commit rather than HEAD. The `rebuild` function adds this automatically; always include it in manual invocations.

### Testing a Feature Branch

The standard way to test changes on a feature branch before merging to `main`:

```bash
# Push your branch first, then:
rebuild -b feat/my-feature          # build + switch from that branch
rebuild --branch feat/my-feature test   # test without committing to boot
```

The `-b`/`--branch` flag sets the flake URL to `github:TristonYoder/nix-config/<branch>`. This works on both NixOS and Darwin hosts. Always push the branch before running — the build pulls from GitHub, not local disk.

### NixOS Hosts

```bash
rebuild          # switch (default)
rebuild boot     # switch at next boot
rebuild test     # test without committing to boot

# Explicit — same as what `rebuild` runs under the hood
sudo nixos-rebuild switch --refresh --flake github:TristonYoder/nix-config
sudo nixos-rebuild switch --refresh --flake github:TristonYoder/nix-config#david
sudo nixos-rebuild switch --refresh --flake github:TristonYoder/nix-config --show-trace
```

### macOS (Darwin) Hosts

```bash
rebuild      # or: hms / hmswitch aliases

# Explicit
sudo darwin-rebuild switch --refresh --flake github:TristonYoder/nix-config
sudo darwin-rebuild switch --refresh --flake github:TristonYoder/nix-config#tyoder-mbp

# First-time setup (nix-darwin not yet installed)
nix build '.#darwinConfigurations.tyoder-mbp.config.system.build.toplevel' --out-link /tmp/result && \
  sudo /tmp/result/sw/bin/darwin-rebuild switch --flake 'github:TristonYoder/nix-config#tyoder-mbp'

# Intel Mac
sudo darwin-rebuild switch --flake 'github:TristonYoder/nix-config#Tristons-MacBook-Pro'
```

### Validation & Testing

**IMPORTANT**: Detect which host you're running on to adjust build/test behavior:

**Current host detection**:
```bash
hostname  # Returns: tyoder-mbp, Tristons-MacBook-Pro, david, tristons-workstation, or pits
```

**Testing policy by host**:

- **On macOS hosts** (tyoder-mbp, Tristons-MacBook-Pro):
  - Do NOT run `nix flake check` or NixOS builds locally - too resource-intensive
  - SSH to target NixOS host for testing instead
  - Can safely run: `nix flake update`, `nix flake show`, `darwin-rebuild build`

- **On NixOS hosts** (david, tristons-workstation, pits):
  - Can run builds and tests directly on the local host
  - No need to SSH elsewhere

**Remote testing from macOS** (when NOT on target host):

Push your branch first, then SSH to david and use the `github:` flake URL — no rsync needed:

```bash
# Dry-run any NixOS host config on david
ssh github-actions@david.vpn.theyoder.family \
  "sudo nixos-rebuild dry-run --flake 'github:TristonYoder/nix-config#david' --refresh"

# Build without activation
ssh github-actions@david.vpn.theyoder.family \
  "sudo nixos-rebuild build --flake 'github:TristonYoder/nix-config#david' --refresh"

# Test a specific branch
ssh github-actions@david.vpn.theyoder.family \
  "sudo nixos-rebuild dry-run --flake 'github:TristonYoder/nix-config/feat/my-branch#david' --refresh"
```

**`--refresh` is required** with `github:` URLs so nix fetches the latest pushed commit rather than a cached ref.

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
│       ├── providers/       # Cross-cutting providers (DNS, monitoring, dashboard, tunnel)
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
    domain = mkOption { type = types.str; default = "service.${config.networking.domain}"; };
    port = mkOption { type = types.int; default = 8080; };
  };

  config = mkIf cfg.enable {
    # Service configuration
    services.servicename.enable = true;

    # Register with the vHosts registry — Caddy, Technitium DNS, Gatus, and Homepage
    # all consume this automatically. Never configure those providers directly.
    modules.services.vHosts.hosts.${cfg.domain} = {
      reverseProxyPort = cfg.port;
      displayName = "Service Name";   # shown in dashboard + monitoring
      category    = "media";          # groups tiles in Homepage dashboard
      icon        = "service-name";   # icon slug (dashicons / selfh.st/sh-icons)
      # monitor   = false;            # set if service won't return HTTP < 500
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
- `modules.services.vHosts.hosts` — unified service registry (consumed by Caddy, Technitium DNS, Gatus monitoring, Homepage dashboard, Cloudflare Tunnel)
- `modules.services.appData` — service data directories (consumed by plain fs or ZFS provider)

**vHosts registry schema** (key = domain or bare subdomain auto-expanded to `<key>.<networking.domain>`):

```nix
modules.services.vHosts.hosts."myservice" = {
  reverseProxyPort = 8080;          # port on localhost
  reverseProxyHost = "other-host";  # optional: proxy to a different host
  displayName      = "My Service";  # dashboard tile label (default: titleCase key)
  category         = "media";       # dashboard group (default: "Services")
  icon             = "my-service";  # dashicons slug (optional)
  monitor          = true;          # include in Gatus monitoring (default: true)
  public           = false;         # expose via Cloudflare Tunnel (default: false)
  serverAliases    = [];            # extra domains for the same vHost
};
```

**Providers** (`modules/services/providers/`):

| Provider | Option path | What it does |
|---|---|---|
| Caddy | `modules.services.infrastructure.caddy` | Reverse proxy for all vHosts |
| Technitium DNS | `modules.services.providers.dns-technitium` | Creates DNS records for all vHosts |
| Gatus monitoring | `modules.services.providers.monitoring` | Status page at `status.<domain>` |
| Homepage dashboard | `modules.services.providers.dashboard-homepage` | App grid at `apps.<domain>` |
| Homarr dashboard | `modules.services.providers.dashboard-homarr` | API-driven dashboard (cross-host) |
| Cloudflare Tunnel | `modules.services.providers.cloudflare-tunnel` | Exposes `public = true` vHosts |

All providers are enabled/disabled independently. The server profile enables Caddy, Technitium, Gatus, and Homepage by default.

### Split-Horizon DNS — The Standing Pattern

**This is how DNS works for every service from here on out.** Every domain we serve — including public, customer-facing ones — resolves two different ways depending on who is asking:

- **Internally** (clients using Technitium as their resolver): the domain resolves to david, so traffic stays on the LAN and never leaves the network.
- **Externally** (public resolvers like 1.1.1.1): the domain resolves to its real public IP — normally Cloudflare's proxy IPs, with the Cloudflare tunnel carrying traffic back to the host.

Registering a vHost is what creates the internal half. `modules.services.providers.dns-technitium` walks the vHosts registry and creates a record pointing at david for every domain, auto-creating a forwarder zone at TLD+1 when the domain isn't under `networking.domain`. The public half lives in Cloudflare and is managed there.

**Consequences when adding a service:**
- Registering a public apex domain (e.g. `carolineyoder.com`) in the vHosts registry is expected and correct, not a mistake. It creates the internal leg of the split.
- Caddy requests certs via Cloudflare DNS-01, so the `CLOUDFLARE_API_TOKEN` must have Zone:DNS:Edit on **every** zone registered as a vHost — including zones outside `theyoder.family`. A missing zone means repeated failed cert issuance, which burns Let's Encrypt rate limits.
- `public = true` is a declaration that the domain is published externally. It only drives routing when `providers.cloudflare-tunnel` is enabled; david currently runs the token-based `infrastructure.cloudflared` instead, whose ingress rules live in the Cloudflare dashboard, not in this repo.
- Don't "fix" a public domain appearing in Technitium by removing it. That breaks internal routing.

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

### Binary Cache Signing Key

The binary cache signing keypair is generated once and never regenerated unless compromised. The private key lives in agenix; the public key is hardcoded in `modules/system/nix-cache.nix` and `common/darwin.nix`.

**To generate (run on any host with nix):**
```bash
nix-store --generate-binary-cache-key nix-cache.theyoder.family \
  /tmp/nix-cache-priv-key.pem /tmp/nix-cache-pub-key.pem

cat /tmp/nix-cache-pub-key.pem
# → e.g. "nix-cache.theyoder.family:abc123..."

cd secrets
./encrypt-secret.sh -n nix-cache-signing-key.age -f /tmp/nix-cache-priv-key.pem
rm /tmp/nix-cache-priv-key.pem /tmp/nix-cache-pub-key.pem
```

**Then paste the public key string into:**
- `modules/system/nix-cache.nix` → `trustedPublicKey` default value
- `common/darwin.nix` → `trusted-public-keys` list

**To retroactively sign existing cached paths after first setup:**
```bash
# On david, after the key is deployed via agenix:
nix store sign --key-file /run/agenix/nix-cache-signing-key --recursive --all
```

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

The CI matrix runs jobs for each host (e.g. `test-configurations (tristons-workstation)`). Each job SSHes to david and runs `nixos-rebuild dry-run --flake github:...#<host> --refresh`. The error will be in the SSH step output — no rsync noise to skip past.

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

### nixos-install OOM on Live Installer (Swapless RAM Disk)
**Host:** any first-time NixOS install via live USB

The live installer environment runs entirely in RAM with **no swap by default**. A heavy closure — e.g. `profiles/workstation.nix`'s gaming module (Steam + 11 emulators, all `mkDefault true`) plus DaVinci Resolve — can exhaust RAM during `nixos-install` and freeze the machine hard enough that even SSH stops responding (timeout during banner exchange, not connection refused). Recovery requires a hard power-cycle, and the live USB itself can get corrupted by the abrupt power loss, requiring a re-flash.

**Mitigations for first install:**
1. Disable heavy optional modules in the host config before the first install (e.g. `modules.services.gaming.enable = false;`), re-enable post-install once the system has its own swap.
2. Create a temporary swapfile on the target disk before running `nixos-install`, to cushion build memory spikes:
   ```bash
   sudo btrfs filesystem mkswapfile --size 16G /mnt/swapfile  # btrfs target
   sudo swapon /mnt/swapfile
   ```
3. Already-built store paths under `/mnt/nix/store` survive a reboot of the live session as long as the target disk partitions aren't reformatted — remount and resume rather than starting over.

**Diagnostics:** `free -h` on the installer (check `Swap: 0B` to confirm no cushion exists) before starting a heavy install.

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

### Headscale 0.25 Policy: Use Email as Username, Not Headscale Username
**Context:** headscale 0.25 changed how users are identified in ACL/SSH policy

headscale 0.25 requires `@`-qualified identifiers in policy group members and tagOwners. But the identifier to use is the **email address** (the OIDC LoginName), not the headscale username:
- `triston@theyoder.family` ✓ (correct — matches what Tailscale clients see as LoginName)
- `tristonyoder@theyoder.family` ✗ (headscale username — won't match in SSH policy evaluation)
- `tristonyoder@id.theyoder.family` ✗ (wrong format)

For the local `github-actions` user (no OIDC/email), use `github-actions@ts.theyoder.family`.

When editing policy via the admin UI or `headscale policy set`, always use email addresses for OIDC users. To check what LoginName headscale assigns to nodes: `sudo tailscale debug netmap | grep LoginName` on any connected node.

To fix a broken policy after a headscale upgrade:
```bash
sudo headscale policy get > /tmp/policy.json
# edit /tmp/policy.json — replace headscale usernames with email addresses
sudo headscale policy set -f /tmp/policy_fixed.json
```

### Headscale Preauthkeys Missing `--tags` Breaks CI SSH
**Context:** GitHub Actions CI runners joining the Tailscale mesh via headscale

Without `--tags tag:github-actions`, preauthkeys produce untagged nodes. The headscale SSH ACL requires `tag:github-actions` as source, so "failed to evaluate SSH policy" is returned (policy can't match — not an explicit deny).

**Always create preauthkeys with:**
```bash
sudo headscale preauthkeys create --user github-actions --reusable --ephemeral --expiration 168h --tags tag:github-actions
```

### /data NFS Automount Fails on tristons-workstation
**Host:** tristons-workstation — NFS home directory backed by david

The `/data` automount involves three interacting systemd units:
- `data.automount` — presents `/data`; first access triggers the mount
- `data.mount` — does the actual NFS connect; defined via `systemd.mounts` (not fstab-generator) so we can attach ordering constraints
- `nfs-david-reachable.service` — waits for the route to `10.150.100.30` and pings david before the mount is attempted

**Ordering cycle (symptom: `data.automount` shows `inactive (dead)` at boot)**

With `DefaultDependencies=yes` (the systemd default), systemd auto-adds `data.automount` to `local-fs.target.wants/`. Any network dependency on the automount unit then creates a cycle:

```
local-fs.target → data.automount → nfs-david-reachable →
network-online.target → ... → local-fs.target
```

systemd resolves ordering cycles by deleting the job — so the automount unit is killed and `/data` never mounts.

**Fix:** `DefaultDependencies=false` in the automount's `unitConfig`. This removes it from `local-fs.target.wants/` so the cycle can't form. Add `Before=umount.target remote-fs.target` and `Conflicts=umount.target` manually (what DefaultDependencies would have contributed for clean shutdown). The network dependency belongs on `data.mount`, not `data.automount`.

**"Network is unreachable" pings (symptom: all pings fail in `nfs-david-reachable` logs)**

`network-online.target` fires as soon as *any* managed interface has an IP — typically `eno1` (`10.150.10.0/24`). The route to `10.150.100.30` lives on `enp7s0` (`10.150.100.0/23`) which completes DHCP slightly later. `ping` exits immediately with "Network is unreachable" when there is no route, so a plain ping loop burns all retries in milliseconds.

**Fix:** Two-phase script in `nfs-david-reachable`:
1. Poll `ip route get 10.150.100.30` up to 30s (sleep 1 between retries) — waits for the enp7s0 route to appear
2. Ping david up to 10 times once the route exists

**`environment.etc` drop-ins on `data.mount` don't work**

NixOS's etc-builder cannot create nested subdirectories (e.g. `systemd/system/data.mount.d/`). Attempting it fails the build with "mkdir: cannot create directory: Permission denied". Use `systemd.mounts` to define the full mount unit instead — it creates `/etc/systemd/system/data.mount` which overrides the fstab-generator's `/run/systemd/generator/data.mount`.

**Diagnostics:**
```bash
systemctl status data.automount data.mount nfs-david-reachable
journalctl -b -u data.automount -u data.mount -u nfs-david-reachable

# Check for ordering cycle (automount should NOT be in local-fs.target.wants)
ls /etc/systemd/system/local-fs.target.wants/

# Check the route exists before manual mount
ip route get 10.150.100.30
```

### Port Conflicts

```bash
# Check port usage
sudo ss -tulpn | grep PORT

# Override port in module options
modules.services.category.servicename.port = 8081;
```

### PostgreSQL Collation Version Mismatch After nixpkgs Bump
**Host:** david — any host running `services.postgresql`

A nixpkgs update that bumps glibc changes glibc's collation library version. PostgreSQL detects this on next boot and refuses further setup work until acknowledged. Symptom: `postgresql-setup.service` fails during `nixos-rebuild switch`, with journal output like:

```
WARNING:  database "postgres" has a collation version mismatch
DETAIL:  The database was created using collation version 2.40, but the operating system provides version 2.42.
```

The overall `switch-to-configuration switch` command exits non-zero (status 4), but this is isolated to the setup unit — the main `postgresql.service` daemon keeps running unaffected, and the rest of the system activates normally.

**Fix** — acknowledge the new collation version on every database (metadata-only, safe to run live, no data touched):

```bash
sudo -u postgres psql -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;"
sudo -u postgres psql -c "ALTER DATABASE template1 REFRESH COLLATION VERSION;"
sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';" \
  | while read -r db; do
      sudo -u postgres psql -c "ALTER DATABASE \"$db\" REFRESH COLLATION VERSION;"
    done

sudo systemctl restart postgresql-setup.service
systemctl status postgresql-setup.service   # should show active (exited)
```

`template1` must be refreshed too — it's the implicit template `ensureDatabases` clones from, so a stale collation there blocks new database creation even after fixing `postgres`.

**Follow-up (not blocking):** glibc collation changes can theoretically reorder sort order and silently corrupt btree indexes on text columns using the default collation. Postgres recommends a `REINDEX` pass after a collation bump; schedule this as low-priority maintenance rather than doing it mid-incident.

### AzuraCast Playlist-Station Autosync

**Host:** david — `modules.services.media.azuracastPlaylistStations`

An hourly systemd timer scans `/data/media/Music/m3u/playlist/` and creates a new AzuraCast station for any m3u file that doesn't already have one (matched by slugified filename against existing station short_names). Each station plays directly from its m3u via Liquidsoap's `remote_url`/`playlist` source — no AzuraCast media-library scan involved, and it auto-refreshes on the file's mtime, so daily-regenerated playlists (e.g. Plexamp/Jellyfin mixes) need no further action.

To run the scan immediately instead of waiting for the hourly timer (e.g. right after adding a new m3u file):

```bash
ssh github-actions@david.vpn.theyoder.family "sudo systemctl start azuracast-playlist-stations.service"

# Watch it run / check the last run's output
ssh github-actions@david.vpn.theyoder.family "sudo journalctl -u azuracast-playlist-stations.service -f"
```

It's idempotent — safe to run anytime, only creates stations for m3u files without one yet.

**If station creation fails with "no available ports for new radio stations":** AzuraCast reserves a full 10-port block per station (frontend/telnet/dj/headroom), not just the 3 ports actually bound. Widen `modules.services.media.azuracast.stationPortMax`, but check `sudo ss -tulpn` on david first for a clean gap rather than just incrementing — the original 9500-9599 range was extended once already and had to be relocated entirely to 23000-24999 to get clear of neighboring services.

## References

Key documentation files in this repository:

- `README.md` - Comprehensive repository overview and quick start
- `modules/README.md` - Module system usage and creation guide
- `profiles/README.md` - Role-based configuration details
- `hosts/README.md` - Adding and managing hosts
- `home/README.md` - User environment customization
- `secrets/README.md` - Secret management with agenix
- `docker/README.md` - Docker Compose service management
