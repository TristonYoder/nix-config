# Configuration Profiles

Role-based configuration profiles for different types of hosts.

## Table of Contents

- [Available Profiles](#available-profiles)
- [Using Profiles](#using-profiles)
- [Overriding Defaults](#overriding-defaults)
- [Profile Comparison](#profile-comparison)
- [Creating New Profiles](#creating-new-profiles)

## Available Profiles

### server.nix
**Full-featured server profile**

Complete infrastructure stack with all services enabled.

**Used by:** `david` (main server)

**Includes:**
- ✅ Infrastructure services (Caddy, PostgreSQL, Tailscale, Technitium)
- ✅ Media services (Jellyfin, Immich, Jellyseerr, Sunshine)
- ✅ Productivity tools (Vaultwarden, n8n, Actual)
- ✅ Storage services (ZFS, NFS, Samba, Syncthing)
- ✅ Development tools (vscode-server, GitHub Actions)

**Resources:** Medium to high CPU, 8GB+ RAM, significant storage

### desktop.nix
**Minimal desktop workstation profile**

Core system with KDE Plasma and essential development tools.

**Used by:** `tristons-desk` (desktop workstation)

**Includes:**
- ✅ Core system modules
- ✅ KDE Plasma 6 desktop environment
- ✅ Development tools (vscode-server)
- ✅ Tailscale VPN
- ✅ Basic system packages

**Resources:** Medium CPU, 4GB+ RAM, moderate storage

### edge.nix
**Lightweight edge server profile**

Optimized for low-resource devices with public internet access.

**Used by:** `pits` (Pi in the Sky / edge VPS)

**Includes:**
- ✅ Core system (headless)
- ✅ Caddy reverse proxy
- ✅ Tailscale VPN
- ✅ vscode-server for remote management

**Optimizations:**
- Reduced journal size (50MB system, 25MB runtime)
- Daily garbage collection (keeps 7 days)
- Auto store optimization
- zram swap (50% of RAM)
- Minimal package footprint

**Resources:** Low CPU (ARM compatible), 1GB+ RAM, limited storage

### darwin.nix
**macOS (nix-darwin) profile**

Native macOS system configuration.

**Used by:** `tyoder-mbp` (MacBook Pro)

**Includes:**
- ✅ macOS system defaults (Dock, Finder, keyboard, etc.)
- ✅ Touch ID for sudo authentication
- ✅ System fonts
- ✅ Homebrew integration (via Home Manager)
- ✅ Mac App Store integration (via Home Manager)

**Features:** Declarative system preferences, native app management

## Using Profiles

### Import in Host Configuration

In your host's `configuration.nix`:

```nix
{
  imports = [
    ../../profiles/server.nix  # or desktop.nix, edge.nix, darwin.nix
  ];
}
```

### Automatic Import via flake.nix

Profiles are automatically imported for each host in `flake.nix`:

```nix
nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
  modules = [
    ./profiles/server.nix  # Profile
    ./hosts/hostname/configuration.nix  # Host-specific
    # ...
  ];
};
```

## Overriding Defaults

Host configurations can override profile settings:

### Disable Specific Services

```nix
{
  imports = [ ../../profiles/server.nix ];
  
  # Disable services you don't want
  modules.services.media.jellyfin.enable = false;
  modules.services.media.jellyseerr.enable = false;
}
```

### Customize Service Options

```nix
{
  imports = [ ../../profiles/server.nix ];
  
  # Override service configuration
  modules.services.media.immich = {
    enable = true;
    domain = "photos.custom.com";
    port = 2284;
  };
}
```

### Add Services to Minimal Profile

```nix
{
  imports = [ ../../profiles/edge.nix ];
  
  # Edge is minimal, add what you need
  modules.services.media.jellyfin.enable = true;
  modules.services.infrastructure.postgresql.enable = true;
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
| **Target** | Main server | Workstation | Pi/VPS | MacBook |

## Creating New Profiles

### 1. Create Profile File

Create `profiles/new-profile.nix`:

```nix
{ config, pkgs, ... }:
{
  # Import common settings if needed
  imports = [
    # Add other profiles or modules
  ];
  
  # Enable specific modules
  modules.services.infrastructure.caddy.enable = true;
  modules.services.development.vscode-server.enable = true;
  
  # Profile-specific packages
  environment.systemPackages = with pkgs; [
    htop
    vim
    git
  ];
  
  # Profile-specific settings
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
```

### 2. Use in Host or flake.nix

Import in host configuration:
```nix
imports = [ ../../profiles/new-profile.nix ];
```

Or add to `flake.nix` for the host.

### 3. Document the Profile

Add to this README with:
- Purpose and use case
- Included services
- Resource requirements
- Example hosts using it

## Common Patterns

### Minimal Profile + Selective Services

```nix
{
  imports = [ ../../profiles/edge.nix ];
  
  # Start minimal, add what you need
  modules.services.media.jellyfin.enable = true;
}
```

### Full Profile - Specific Services

```nix
{
  imports = [ ../../profiles/server.nix ];
  
  # Start with everything, disable what you don't want
  modules.services.media.jellyseerr.enable = false;
  modules.services.productivity.n8n.enable = false;
}
```

### Desktop with Development

```nix
{
  imports = [ ../../profiles/desktop.nix ];
  
  # Desktop + additional dev tools
  modules.services.development.github-actions.enable = true;
  modules.services.infrastructure.postgresql.enable = true;
}
```

## Best Practices

1. **Keep profiles focused** - Each profile should serve a specific role
2. **Use for common patterns** - Profiles are for repeated configurations
3. **Override in hosts** - Host-specific customizations go in host configs, not profiles
4. **Document changes** - Update this README when modifying profiles
5. **Test thoroughly** - Profile changes affect multiple hosts

## Additional Resources

- [Main README](../README.md) - Repository overview
- [Host Configurations](../hosts/README.md) - Per-host configuration
- [Modules](../modules/README.md) - Available modules and services

---

**Available Profiles:** 4 (server, desktop, edge, darwin)  
**Hosts Using Profiles:** 4 (david, pits, tristons-desk, tyoder-mbp)
