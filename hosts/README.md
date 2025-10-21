# Host Configurations

Per-host NixOS and macOS configurations managed through this flake.

## Table of Contents

- [Configured Hosts](#configured-hosts)
- [Quick Commands](#quick-commands)
- [Adding a New Host](#adding-a-new-host)
- [Configuration Patterns](#configuration-patterns)
- [Host-Specific Overrides](#host-specific-overrides)
- [Troubleshooting](#troubleshooting)

## Configured Hosts

### NixOS Hosts

#### david (Main Server)
- **Profile:** [server](../profiles/server.nix)
- **Architecture:** x86_64-linux
- **User:** tristonyoder
- **Auto-Deploy:** ✅ GitHub Actions enabled
- **Services:** Full stack (infrastructure, media, productivity, storage, development)

#### pits (Edge Server / Pi in the Sky)
- **Profile:** [edge](../profiles/edge.nix)
- **Architecture:** aarch64-linux (Raspberry Pi compatible)
- **User:** tristonyoder
- **Auto-Deploy:** ✅ GitHub Actions enabled
- **Services:** Minimal (Caddy reverse proxy, Tailscale VPN)
- **Purpose:** Public-facing reverse proxy optimized for low-resource devices
- **Documentation:** [pits/README.md](pits/README.md)

#### tristons-desk (Desktop Workstation)
- **Profile:** [desktop](../profiles/desktop.nix)
- **Architecture:** x86_64-linux
- **User:** tristonyoder
- **Auto-Deploy:** ✅ GitHub Actions enabled
- **Services:** Minimal desktop (KDE Plasma, development tools)

### macOS Hosts

#### tyoder-mbp (MacBook Pro)
- **Profile:** [darwin](../profiles/darwin.nix)
- **Architecture:** aarch64-darwin (Apple Silicon M1)
- **User:** tyoder
- **Auto-Deploy:** ➖ Manual only
- **Features:** Declarative macOS system preferences, Homebrew, Mac App Store

## Quick Commands

### Auto-Detection

Systems automatically detect their hostname:

```bash
# On any NixOS host
sudo nixos-rebuild switch --flake .

# On macOS
darwin-rebuild switch --flake .
```

### Explicit Host Selection

```bash
# NixOS
sudo nixos-rebuild switch --flake .#david
sudo nixos-rebuild switch --flake .#pits
sudo nixos-rebuild switch --flake .#tristons-desk

# macOS
darwin-rebuild switch --flake .#tyoder-mbp
```

### Testing

```bash
# Test without applying (activates but not bootable)
sudo nixos-rebuild test --flake .#hostname

# Build without activating
sudo nixos-rebuild build --flake .#hostname
darwin-rebuild build --flake .#hostname

# Dry run (show what would change)
sudo nixos-rebuild dry-run --flake .#hostname
```

## Adding a New Host

### 1. Create Host Directory

```bash
mkdir -p hosts/new-hostname
```

### 2. Create Configuration File

Create `hosts/new-hostname/configuration.nix`:

```nix
{ config, pkgs, lib, ... }:
{
  networking.hostName = "new-hostname";
  system.stateVersion = "25.05";  # Current NixOS version
  
  # Import appropriate profile
  imports = [
    ../../profiles/server.nix  # or desktop.nix, edge.nix
  ];
  
  # Host-specific customizations
  # ...
}
```

### 3. Generate Hardware Configuration (NixOS Only)

On the target NixOS machine:

```bash
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Copy to `hosts/new-hostname/hardware-configuration.nix` in your repo.

### 4. Add to flake.nix

**For NixOS:**

```nix
nixosConfigurations.new-hostname = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";  # or aarch64-linux
  modules = [
    ./common.nix
    ./profiles/server.nix  # Choose appropriate profile
    ./hosts/new-hostname/configuration.nix
    ./hosts/new-hostname/hardware-configuration.nix
    ./modules
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.username = import ./home/username.nix;
    }
  ];
};
```

**For macOS (Darwin):**

```nix
darwinConfigurations.new-hostname = nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";  # or x86_64-darwin
  modules = [
    ./common.nix
    ./profiles/darwin.nix
    ./hosts/new-hostname/configuration.nix
    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.username = import ./home/username.nix;
    }
  ];
};
```

### 5. Build and Deploy

```bash
# Validate
nix flake check

# Build locally first
nix build .#nixosConfigurations.new-hostname.config.system.build.toplevel

# Deploy
sudo nixos-rebuild switch --flake .#new-hostname
```

### 6. Enable GitHub Actions (Optional)

For automated deployment:

1. On the host, enable the module:
   ```nix
   modules.services.development.github-actions.enable = true;
   ```

2. Add to `.github/workflows/test-nixos-config.yml` matrix
3. Add to `.github/workflows/deploy-nixos-config.yml` host list

See [../.github/workflows/](../.github/workflows/) for CI/CD details.

## Configuration Patterns

### Minimal Server

```nix
{
  imports = [ ../../profiles/edge.nix ];
  networking.hostName = "minimal-server";
  
  # Edge profile provides Caddy + Tailscale
  # Add only what you need
}
```

### Full-Featured Server

```nix
{
  imports = [ ../../profiles/server.nix ];
  networking.hostName = "full-server";
  
  # Server profile enables all services
  # Override specific settings
  modules.services.media.immich.domain = "photos.example.com";
}
```

### Desktop Workstation

```nix
{
  imports = [ ../../profiles/desktop.nix ];
  networking.hostName = "workstation";
  
  # Desktop profile provides KDE + basics
  # Add development tools
  modules.services.development.github-actions.enable = true;
}
```

### macOS Laptop

```nix
{
  imports = [ ../../profiles/darwin.nix ];
  networking.hostName = "laptop";
  
  # Darwin profile provides system defaults
  # Apps managed via Home Manager (see home/tyoder.nix)
}
```

## Host-Specific Overrides

Override profile defaults in host configuration:

```nix
{
  imports = [ ../../profiles/server.nix ];
  
  # Disable a service enabled by profile
  modules.services.media.jellyseerr.enable = false;
  
  # Customize service options
  modules.services.media.jellyfin = {
    enable = true;
    domain = "media.custom.com";
  };
  
  # Add host-specific packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    custom-package
  ];
  
  # Host-specific networking
  networking.interfaces.eth0.ipv4.addresses = [{
    address = "192.168.1.100";
    prefixLength = 24;
  }];
}
```

## Troubleshooting

### Hardware Configuration Issues

```bash
# Regenerate on the actual machine
sudo nixos-generate-config --show-hardware-config

# Copy to repo
scp root@hostname:/etc/nixos/hardware-configuration.nix hosts/hostname/
```

### Hostname Mismatch

Ensure hostname in configuration matches actual hostname:

```bash
# Check current hostname
hostname

# Should match configuration.nix
networking.hostName = "actual-hostname";
```

If they don't match, either:
1. Change `networking.hostName` in config
2. Or change system hostname: `sudo hostnamectl set-hostname new-name`

### Build Failures

```bash
# Check flake syntax
nix flake check

# Build without applying
sudo nixos-rebuild build --flake .#hostname

# Show detailed errors with trace
sudo nixos-rebuild switch --flake .#hostname --show-trace
```

### Remote Deployment Issues

```bash
# Build locally, deploy to remote
nixos-rebuild switch --flake .#hostname \
  --target-host user@hostname \
  --build-host localhost

# Check SSH access
ssh user@hostname "echo success"
```

### macOS System Defaults Not Applying

```bash
# Some settings require logout/restart
killall Dock && killall Finder

# Or full logout
# Log out and back in
```

## Additional Resources

- [Main README](../README.md) - Repository overview
- [Profiles](../profiles/README.md) - Available configuration profiles
- [Modules](../modules/README.md) - System modules and services
- [Home Manager](../home/README.md) - User environment configuration

---

**Managed Hosts:** 4 (david, pits, tristons-desk, tyoder-mbp)  
**Auto-Deploy:** 3 NixOS hosts via GitHub Actions  
**Platforms:** NixOS (x86_64, aarch64) + macOS (aarch64)
