# Modular NixOS Configuration Guide

This document explains the new modular structure of the NixOS configuration and how to use it.

## Overview

The configuration has been refactored into a modular system where each service, hardware component, and system setting is encapsulated in its own module with custom enable options. This makes the configuration much more maintainable and easier to understand.

## Directory Structure

```
.
├── configuration.nix           # Main config - just enable/disable modules
├── flake.nix                   # Flake inputs and system definition
├── hardware-configuration.nix  # Auto-generated hardware config (DO NOT EDIT)
│
├── modules/
│   ├── default.nix             # Imports all modules
│   ├── hardware/               # Hardware-specific modules
│   │   ├── nvidia.nix          # NVIDIA GPU configuration
│   │   └── boot.nix            # Bootloader configuration
│   ├── system/                 # System-level modules
│   │   ├── core.nix            # Nix settings, locale, time zone
│   │   ├── networking.nix      # Network and firewall
│   │   ├── users.nix           # User accounts
│   │   └── desktop.nix         # KDE Plasma desktop
│   └── services/               # Service modules
│       ├── infrastructure/     # Core infrastructure
│       │   ├── caddy.nix       # Reverse proxy
│       │   ├── cloudflared.nix # Cloudflare tunnel
│       │   ├── postgresql.nix  # Database
│       │   ├── tailscale.nix   # VPN
│       │   └── technitium.nix  # DNS server
│       ├── media/              # Media services
│       │   ├── immich.nix      # Photo management
│       │   ├── jellyfin.nix    # Media server
│       │   ├── jellyseerr.nix  # Media requests
│       │   └── sunshine.nix    # Game streaming
│       ├── productivity/       # Productivity tools
│       │   ├── vaultwarden.nix # Password manager
│       │   ├── n8n.nix         # Workflow automation
│       │   └── actual.nix      # Budget app
│       ├── storage/            # Storage services
│       │   ├── zfs.nix         # ZFS filesystem
│       │   ├── nfs.nix         # NFS server
│       │   ├── samba.nix       # SMB/CIFS
│       │   └── syncthing.nix   # File sync
│       └── development/        # Development tools
│           ├── vscode-server.nix
│           └── github-actions.nix
│
├── docker/                     # Docker services (organized)
│   ├── docker.nix              # Core Docker setup
│   ├── watchtower.nix          # Container updates
│   ├── media/                  # Media containers
│   ├── websites/               # Website containers
│   └── productivity/           # Productivity containers
│
└── secrets/                    # agenix encrypted secrets
    ├── secrets.nix             # Encryption configuration
    ├── README.md               # Secrets documentation
    └── *.age                   # Encrypted secret files

```

## How to Use

### Enabling/Disabling Services

Edit `configuration.nix` and toggle module enable flags:

```nix
# Enable a service
modules.services.media.jellyfin.enable = true;

# Disable a service
modules.services.media.jellyfin.enable = false;
```

### Customizing Service Options

Each module has customizable options. Example for Immich:

```nix
modules.services.media.immich = {
  enable = true;
  domain = "photos.custom.domain";  # Override default
  port = 2283;                       # Can change port
};
```

### Module Options

To see all available options for a module, check the module file or use:

```bash
nixos-option modules.services.media.immich
```

## Common Tasks

### Adding a New Service

1. Create a new module file in the appropriate category
2. Follow the module template pattern (see examples)
3. Add the module to the category's `default.nix`
4. Enable it in `configuration.nix`

### Module Template

```nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.category.servicename;
in
{
  options.modules.services.category.servicename = {
    enable = mkEnableOption "Service Description";
    
    # Add options here
    domain = mkOption {
      type = types.str;
      default = "service.domain.com";
      description = "Domain for service";
    };
  };

  config = mkIf cfg.enable {
    # Service configuration
    services.servicename = {
      enable = true;
      # ... service config
    };
    
    # Optional: Caddy reverse proxy
    services.caddy.virtualHosts.${cfg.domain} = mkIf config.modules.services.infrastructure.caddy.enable {
      extraConfig = ''
        reverse_proxy http://localhost:port
      '';
    };
  };
}
```

### Rebuilding the System

```bash
# Test the configuration
sudo nixos-rebuild test --flake .#david

# Apply and make bootable
sudo nixos-rebuild switch --flake .#david

# Just build without applying
sudo nixos-rebuild build --flake .#david
```

### Managing Secrets with agenix

See `secrets/README.md` for detailed instructions.

Quick reference:
```bash
# Edit a secret
nix develop
agenix -e secretname.age

# Rekey after adding keys
agenix -r
```

## Configuration Benefits

### Before Refactoring
- 386-line monolithic `apps.nix`
- Hardcoded secrets
- Difficult to find specific service configs
- No easy way to toggle services

### After Refactoring
- Clean 100-line `configuration.nix` with just enable flags
- Secrets managed securely with agenix
- Each service in its own ~50-line module
- Toggle any service with one line
- Type-safe configuration with NixOS options
- Self-documenting through option descriptions

## Docker Services

Docker services are organized by category but remain as individual files since they're generated by `compose2nix`:

- `docker/media/` - Media-related containers
- `docker/websites/` - Website containers  
- `docker/productivity/` - Productivity app containers

To regenerate a docker service from compose file:
```bash
cd docker/dockercompose
compose2nix -inputs=docker-compose_service.yml -output=../category/service.nix
```

## Troubleshooting

### Service Not Starting

1. Check if the service is enabled in `configuration.nix`
2. Check module dependencies (e.g., Caddy needs to be enabled for reverse proxy)
3. View service logs: `journalctl -u servicename -f`

### Module Errors

1. Check syntax with: `nix flake check`
2. Build without applying: `nixos-rebuild build --flake .#david`
3. Review error messages - they'll point to the specific module

### Secrets Not Decrypting

1. Ensure SSH host key is correct in `secrets/secrets.nix`
2. Verify secret file exists and has correct permissions
3. Check agenix configuration in the service module

## Migration Notes

Old configuration files have been renamed with `.old` extension and are ignored by git. They're kept as reference but not used by the system:

- `modules/services/apps.nix.old` - Original monolithic config
- `modules/services/nas.nix.old` - Migrated to storage modules
- `modules/services/caddy-hosts.nix.old` - Integrated into service modules
- `modules/services/github-actions.nix.old` - Moved to development/

These can be safely deleted once you've verified everything works.

## Additional Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)
- [agenix Documentation](https://github.com/ryantm/agenix)
- [compose2nix](https://github.com/aksiksi/compose2nix)

