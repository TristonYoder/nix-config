# Configuration Profiles

Role-based configuration profiles for different types of hosts.

## Available Profiles

### server.nix
**Full-featured server profile**

Enables all infrastructure, media, productivity, and storage services.

**Used by:** `david` (main server)

**Includes:**
- ✅ All infrastructure services (Caddy, PostgreSQL, Tailscale, Technitium)
- ✅ Media services (Jellyfin, Immich, Jellyseerr, Sunshine)
- ✅ Productivity tools (Vaultwarden, n8n, Actual)
- ✅ Storage services (ZFS, NFS, Samba, Syncthing)
- ✅ Development tools (vscode-server, GitHub Actions)

**Resource Requirements:**
- Medium to high CPU
- 8GB+ RAM recommended
- Significant storage

### desktop.nix
**Minimal desktop workstation profile**

Provides core system and desktop environment with minimal services.

**Used by:** `tristons-desk` (desktop workstation)

**Includes:**
- ✅ Core system modules
- ✅ Desktop environment (KDE Plasma 6)
- ✅ Development tools (vscode-server)
- ✅ Tailscale for VPN access
- ✅ Basic system packages

**Resource Requirements:**
- Medium CPU
- 4GB+ RAM recommended
- Moderate storage

### edge.nix
**Lightweight edge server profile**

Optimized for low-resource devices like Raspberry Pi with public internet access.

**Used by:** `pits` (Pi in the Sky / edge VPS)

**Includes:**
- ✅ Core system (headless)
- ✅ Caddy reverse proxy
- ✅ Tailscale VPN
- ✅ vscode-server for remote management
- ✅ Aggressive optimizations for low resources

**Optimizations:**
- Reduced journal size (50MB system, 25MB runtime)
- Daily garbage collection (keeps 7 days)
- Auto store optimization enabled
- zram swap (50% of RAM)
- Minimal package footprint

**Resource Requirements:**
- Low CPU (ARM compatible)
- 1GB+ RAM minimum
- Limited storage

### darwin.nix
**macOS (nix-darwin) profile**

System configuration for macOS machines.

**Used by:** `tyoder-mbp` (MacBook Pro)

**Includes:**
- ✅ macOS system defaults (Dock, Finder, keyboard, etc.)
- ✅ Touch ID for sudo authentication
- ✅ System fonts
- ✅ Homebrew integration (via Home Manager)
- ✅ Mac App Store integration (via Home Manager)

**Features:**
- Declarative system preferences
- Native macOS app management
- Shell environment configuration

## Using Profiles

### In Host Configuration

Import the appropriate profile in your host's `configuration.nix`:

```nix
{
  imports = [
    ../../profiles/server.nix  # or desktop.nix, edge.nix
  ];
}
```

### In flake.nix

Profiles are automatically imported for each host:

```nix
nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
  modules = [
    ./profiles/server.nix  # Profile
    ./hosts/hostname/configuration.nix  # Host-specific
    # ...
  ];
};
```

## Overriding Profile Settings

Host configurations can override profile defaults:

```nix
{
  imports = [
    ../../profiles/server.nix
  ];
  
  # Override: Disable a service enabled by profile
  modules.services.media.jellyfin.enable = false;
  
  # Override: Customize a service option
  modules.services.media.immich.domain = "photos.custom.com";
}
```

## Profile Comparison

| Feature | Server | Desktop | Edge | Darwin |
|---------|--------|---------|------|--------|
| **Infrastructure** | ✅ Full | ❌ No | ✅ Basic | ❌ No |
| **Media Services** | ✅ All | ❌ No | ❌ No | ❌ No |
| **Productivity** | ✅ All | ❌ No | ❌ No | ✅ Via Homebrew |
| **Storage** | ✅ All | ❌ No | ❌ No | ❌ No |
| **Desktop** | ❌ No | ✅ KDE | ❌ No | ✅ macOS Native |
| **Development** | ✅ All | ✅ Basic | ✅ Remote | ✅ Full |
| **Optimizations** | Standard | Standard | ✅ Aggressive | macOS Native |

## Creating a New Profile

1. Create `profiles/new-profile.nix`:

```nix
{ config, pkgs, ... }:

{
  # Import common settings
  imports = [
    ./common.nix  # If you create one
  ];
  
  # Enable specific modules
  modules.services.infrastructure.caddy.enable = true;
  modules.services.development.vscode-server.enable = true;
  
  # Custom packages
  environment.systemPackages = with pkgs; [
    htop
    neofetch
  ];
  
  # Profile-specific settings
  nix.gc.automatic = true;
}
```

2. Use in host configuration or flake.nix

## Best Practices

1. **Keep profiles focused:** Each profile should serve a specific role
2. **Use imports:** Share common configuration where appropriate
3. **Override in hosts:** Host-specific customizations go in host configs
4. **Document changes:** Update this README when modifying profiles
5. **Test changes:** Build and test before deploying

## Common Patterns

### Minimal Profile + Selective Services

```nix
{
  imports = [ ../../profiles/edge.nix ];
  
  # Add just what you need
  modules.services.media.jellyfin.enable = true;
}
```

### Server Profile - Specific Services

```nix
{
  imports = [ ../../profiles/server.nix ];
  
  # Disable what you don't want
  modules.services.media.jellyseerr.enable = false;
}
```

### Desktop with Development Tools

```nix
{
  imports = [ ../../profiles/desktop.nix ];
  
  # Add development services
  modules.services.development.github-actions.enable = true;
  modules.services.infrastructure.postgresql.enable = true;
}
```

## Resources

- [Host Configurations](../hosts/) - Per-host configuration files
- [Modules](../modules/) - Available modules and services
- [Multi-Host Setup](../docs/MULTI-HOST-SETUP.md) - Complete setup guide

---

**Note:** Profiles provide sensible defaults for different use cases. Customize in host configurations as needed.

