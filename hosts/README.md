# Host Configurations

Per-host NixOS and macOS configurations managed through this flake.

## Configured Hosts

### NixOS Hosts

#### david (Main Server)
- **System:** x86_64-linux
- **Profile:** [server](../profiles/server.nix)
- **User:** tristonyoder
- **Location:** `hosts/david/`
- **Services:** Full stack (infrastructure, media, productivity, storage, development)

**Features:**
- All infrastructure services
- Media server (Jellyfin, Immich)
- Productivity tools (Vaultwarden, n8n, Actual)
- Storage services (ZFS, NFS, Samba, Syncthing)
- Automated GitHub Actions deployment ✅

#### pits (Edge Server / Pi in the Sky)
- **System:** aarch64-linux (Raspberry Pi compatible)
- **Profile:** [edge](../profiles/edge.nix)
- **User:** tristonyoder
- **Location:** `hosts/pits/`
- **Services:** Minimal (Caddy, Tailscale)

**Features:**
- Public-facing reverse proxy
- Optimized for low-resource devices
- Aggressive resource optimizations
- Automated GitHub Actions deployment ✅

**Documentation:**
- [Setup Guide](pits/README.md)
- [Installation Guide](pits/INSTALLATION.md)
- [Bootstrap Guide](pits/BOOTSTRAP.md)

#### tristons-desk (Desktop Workstation)
- **System:** x86_64-linux
- **Profile:** [desktop](../profiles/desktop.nix)
- **User:** tristonyoder
- **Location:** `hosts/tristons-desk/`
- **Services:** Minimal desktop (KDE Plasma, development tools)

**Features:**
- KDE Plasma 6 desktop environment
- Development tools (vscode-server)
- Tailscale VPN
- Automated GitHub Actions deployment ✅

### macOS Hosts

#### tyoder-mbp (MacBook Pro)
- **System:** aarch64-darwin (Apple Silicon M1)
- **Profile:** [darwin](../profiles/darwin.nix)
- **User:** tyoder
- **Location:** `hosts/tyoder-mbp/`
- **Services:** Homebrew, Mac App Store, development tools

**Features:**
- Declarative macOS system preferences
- Homebrew cask management
- Mac App Store app management
- Shell environment (zsh, Oh My Zsh, Powerlevel10k)

## Quick Commands

### Auto-Detection

Systems automatically detect their hostname:

```bash
# On any NixOS host (auto-detects)
sudo nixos-rebuild switch --flake .

# On macOS (auto-detects)
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

### Test Before Applying

```bash
# Test without applying
sudo nixos-rebuild test --flake .#hostname

# Build without activating
sudo nixos-rebuild build --flake .#hostname
darwin-rebuild build --flake .#hostname

# Dry run
sudo nixos-rebuild dry-run --flake .#hostname
```

## Adding a New Host

### 1. Create Host Directory

```bash
mkdir -p hosts/new-hostname
```

### 2. Create Configuration

Create `hosts/new-hostname/configuration.nix`:

```nix
{ config, pkgs, lib, ... }:

{
  networking.hostName = "new-hostname";
  system.stateVersion = "25.05";  # NixOS version
  
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

Copy to `hosts/new-hostname/hardware-configuration.nix`

### 4. Add to flake.nix

**For NixOS:**

```nix
nixosConfigurations.new-hostname = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";  # or aarch64-linux
  modules = [
    ./common.nix
    ./profiles/server.nix  # Choose profile
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
# Build locally
nix build .#nixosConfigurations.new-hostname.config.system.build.toplevel

# Or deploy directly
sudo nixos-rebuild switch --flake .#new-hostname
```

### 6. Add to GitHub Actions (Optional)

To enable automated testing and deployment:

1. Edit `.github/workflows/test-nixos-config.yml`:
   ```yaml
   matrix:
     host: 
       - name: new-hostname
         hostname: new-hostname
   ```

2. Edit `.github/workflows/deploy-nixos-config.yml`:
   ```yaml
   ALL_HOSTS='["david", "pits", "tristons-desk", "new-hostname"]'
   ```

3. On the host, enable GitHub Actions module:
   ```nix
   modules.services.development.github-actions.enable = true;
   ```

See [../.github/workflows/README.md](../.github/workflows/README.md) for complete CI/CD setup.

## Host Configuration Structure

Each host directory should contain:

```
hosts/hostname/
├── configuration.nix           # Host-specific configuration
└── hardware-configuration.nix  # Hardware settings (NixOS only)
```

Optional documentation:
```
hosts/hostname/
├── README.md                   # Host-specific documentation
├── INSTALLATION.md             # Installation guide
└── BOOTSTRAP.md                # Quick setup guide
```

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
  # Apps managed via Home Manager
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
  ];
}
```

## Troubleshooting

### Hardware Configuration Issues

```bash
# Regenerate on the actual machine
sudo nixos-generate-config --show-hardware-config
```

### Hostname Mismatch

Ensure hostname in configuration matches actual hostname:

```bash
# Check current hostname
hostname

# Should match configuration.nix
networking.hostName = "actual-hostname";
```

### Build Failures

```bash
# Check flake syntax
nix flake check

# Build without applying
sudo nixos-rebuild build --flake .#hostname

# Check for detailed errors
sudo nixos-rebuild switch --flake .#hostname --show-trace
```

### macOS System Defaults Not Applying

```bash
# Some settings require logout
killall Dock && killall Finder

# Or full logout/restart
```

## Resources

- [Profiles](../profiles/README.md) - Available configuration profiles
- [Modules](../modules/README.md) - System modules and services
- [Home Manager](../home/README.md) - User environment configuration
- [GitHub Actions](../.github/workflows/README.md) - Automated deployment
- [Main README](../README.md) - Repository overview

---

**Managed Hosts:** 4 (david, pits, tristons-desk, tyoder-mbp)  
**Auto-Deploy:** 3 NixOS hosts via GitHub Actions  
**Last Updated:** October 13, 2025

