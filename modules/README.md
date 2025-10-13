# NixOS Modules

Custom NixOS modules for managing system configuration with a modular, type-safe approach.

## Structure

```
modules/
├── default.nix          # Imports all module categories
├── hardware/            # Hardware-specific modules
├── system/              # System-level configuration
└── services/            # Service modules
    ├── infrastructure/  # Core infrastructure (Caddy, PostgreSQL, Tailscale)
    ├── media/           # Media services (Jellyfin, Immich, Jellyseerr)
    ├── productivity/    # Productivity tools (Vaultwarden, n8n, Actual)
    ├── storage/         # Storage services (ZFS, NFS, Samba, Syncthing)
    └── development/     # Development tools (vscode-server, GitHub Actions)
```

## Module System

Each module provides:
- **Enable option:** Simple on/off toggle
- **Configuration options:** Customizable settings with defaults
- **Type safety:** NixOS validates all options
- **Documentation:** Self-documenting through option descriptions
- **Dependencies:** Conditional service configuration

## Usage

### Enable a Service

In your host configuration:

```nix
{
  modules.services.media.jellyfin.enable = true;
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
nixos-option modules.services.media.immich
```

## Module Categories

### Hardware (`hardware/`)

- **nvidia.nix** - NVIDIA GPU configuration
- **boot.nix** - Bootloader and GRUB theming

### System (`system/`)

- **core.nix** - Nix settings, locale, timezone, packages
- **networking.nix** - Network and firewall configuration
- **users.nix** - User account management
- **desktop.nix** - KDE Plasma 6 desktop environment

### Infrastructure (`services/infrastructure/`)

- **caddy.nix** - Reverse proxy with Cloudflare DNS
- **cloudflared.nix** - Cloudflare tunnel
- **postgresql.nix** - Database server
- **tailscale.nix** - VPN with routing features
- **technitium.nix** - DNS server

### Media (`services/media/`)

- **immich.nix** - Photo management with public sharing
- **jellyfin.nix** - Media server with hardware transcoding
- **jellyseerr.nix** - Media request management
- **sunshine.nix** - Game streaming

### Productivity (`services/productivity/`)

- **vaultwarden.nix** - Password manager
- **n8n.nix** - Workflow automation
- **actual.nix** - Budget application

### Storage (`services/storage/`)

- **zfs.nix** - ZFS filesystem management
- **nfs.nix** - NFS server
- **samba.nix** - SMB/CIFS file sharing
- **syncthing.nix** - File synchronization

### Development (`services/development/`)

- **vscode-server.nix** - Remote development
- **github-actions.nix** - CI/CD integration

## Creating a New Module

1. Create the module file in the appropriate category
2. Follow the module template pattern:

```nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.category.servicename;
in
{
  options.modules.services.category.servicename = {
    enable = mkEnableOption "Service Description";
    
    domain = mkOption {
      type = types.str;
      default = "service.domain.com";
      description = "Domain for service";
    };
  };

  config = mkIf cfg.enable {
    # Service configuration
    services.servicename.enable = true;
    
    # Optional: Caddy reverse proxy integration
    services.caddy.virtualHosts.${cfg.domain} = 
      mkIf config.modules.services.infrastructure.caddy.enable {
        extraConfig = ''
          reverse_proxy http://localhost:port
        '';
      };
  };
}
```

3. Import the module in the category's `default.nix`
4. Enable it in your host configuration

## Benefits

| Aspect | Before | After |
|--------|--------|-------|
| **Main Config** | 214 lines, mixed concerns | ~100 lines, just enable flags |
| **Service Files** | 386-line monolith | ~50 lines per module |
| **Discoverability** | Search large files | Navigate by category |
| **Toggling Services** | Comment/uncomment blocks | Single enable flag |
| **Type Safety** | Basic Nix validation | Full NixOS option system |

## Module Template

When creating a new module, follow this pattern:

```nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.category.servicename;
in
{
  options.modules.services.category.servicename = {
    enable = mkEnableOption "Service Description";
    
    domain = mkOption {
      type = types.str;
      default = "service.domain.com";
      description = "Domain for service";
    };
    
    port = mkOption {
      type = types.int;
      default = 8080;
      description = "Port for service";
    };
  };

  config = mkIf cfg.enable {
    # Service configuration
    services.servicename = {
      enable = true;
      # ... service config
    };
    
    # Optional: Caddy reverse proxy integration
    services.caddy.virtualHosts.${cfg.domain} = 
      mkIf config.modules.services.infrastructure.caddy.enable {
        extraConfig = ''
          reverse_proxy http://localhost:${toString cfg.port}
        '';
      };
    
    # Optional: Firewall rules
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

## Common Tasks

### Enable/Disable Services

In your host configuration:

```nix
{
  # Enable with defaults
  modules.services.media.jellyfin.enable = true;
  
  # Disable
  modules.services.media.jellyfin.enable = false;
}
```

### Customize Service Options

```nix
{
  modules.services.media.immich = {
    enable = true;
    domain = "photos.custom.domain";
    port = 2283;
    mediaLocation = "/custom/path";
  };
}
```

### Check Available Options

```bash
nixos-option modules.services.media.immich
```

### Rebuild After Changes

```bash
# Test the configuration
sudo nixos-rebuild test --flake .

# Apply and make bootable
sudo nixos-rebuild switch --flake .

# Just build without applying
sudo nixos-rebuild build --flake .
```

## Troubleshooting

### Service Not Starting

1. Check if enabled in configuration
2. Check module dependencies (e.g., Caddy needs to be enabled for reverse proxy)
3. View service logs: `journalctl -u servicename -f`

### Module Errors

1. Check syntax: `nix flake check`
2. Build without applying: `nixos-rebuild build --flake .`
3. Review error messages - they point to the specific module

### Secrets Not Decrypting

1. Ensure SSH host key is correct in `secrets/secrets.nix`
2. Verify secret file exists and has correct permissions
3. Check agenix configuration in the service module

## Module Benefits

| Aspect | Before Refactoring | After Refactoring |
|--------|-------------------|-------------------|
| **Main Config** | 214 lines, mixed concerns | ~100 lines, just enable flags |
| **Service Files** | 386-line monolith | ~50 lines per module |
| **Discoverability** | Search large files | Navigate by category |
| **Toggling Services** | Comment/uncomment blocks | Single enable flag |
| **Type Safety** | Basic Nix validation | Full NixOS option system |
| **Documentation** | External docs needed | Self-documenting options |

## Migration Notes

Old configuration files have been renamed with `.old` extension:
- `modules/services/apps.nix.old` - Original monolithic config
- `modules/services/nas.nix.old` - Migrated to storage modules
- `modules/services/caddy-hosts.nix.old` - Integrated into service modules
- `modules/services/github-actions.nix.old` - Moved to development/

These can be safely deleted once verified.

## Documentation

- [Host Configurations](../hosts/README.md) - Per-host setup guide
- [Profiles](../profiles/README.md) - Role-based configuration profiles
- [Docker Services](../docker/README.md) - Container management
- [NixOS Module System](https://nixos.org/manual/nixos/stable/#sec-writing-modules) - Official docs

---

**Modules:** 40+ custom modules  
**Categories:** 8 (hardware, system, infrastructure, media, productivity, storage, development)  
**Type Safety:** Full NixOS option validation  
**Status:** Active and maintained

