# NixOS Modules

Custom NixOS modules for managing system configuration with a modular, type-safe approach.

## Table of Contents

- [Overview](#overview)
- [Usage](#usage)
  - [Enable a Service](#enable-a-service)
  - [Customize Options](#customize-options)
  - [Check Available Options](#check-available-options)
- [Module Categories](#module-categories)
- [Creating New Modules](#creating-new-modules)
- [Benefits](#benefits)

## Overview

Each module provides:
- **Enable option** - Simple on/off toggle
- **Configuration options** - Customizable settings with defaults
- **Type safety** - NixOS validates all options
- **Documentation** - Self-documenting through option descriptions
- **Auto-integration** - Optional Caddy reverse proxy configuration

## Usage

### Enable a Service

In your host configuration (`hosts/<hostname>/configuration.nix`):

```nix
{
  modules.services.media.jellyfin.enable = true;
}
```

Rebuild to apply:
```bash
sudo nixos-rebuild switch --flake .
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
# View all options for a module
nixos-option modules.services.media.immich

# Or read the module source
cat modules/services/media/immich.nix
```

## Module Categories

### Hardware (`hardware/`)

- **nvidia.nix** - NVIDIA GPU configuration with CUDA support
- **boot.nix** - Bootloader and GRUB theming

### System (`system/`)

- **core.nix** - Nix settings, locale, timezone, base packages
- **networking.nix** - Network and firewall configuration
- **users.nix** - User account management
- **desktop.nix** - KDE Plasma 6 desktop environment

### Infrastructure (`services/infrastructure/`)

- **caddy.nix** - Reverse proxy with Cloudflare DNS integration
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

- **vscode-server.nix** - Remote development with VS Code
- **github-actions.nix** - CI/CD integration for automated deployments
- **kasm.nix** - Browser-based development environments

### Communication (`services/communication/`)

- **matrix-synapse.nix** - Matrix homeserver
- **pixelfed.nix** - Federated photo sharing
- **mautrix-imessage.nix** - iMessage bridge for Matrix
- **mautrix-groupme.nix** - GroupMe bridge for Matrix
- **wellknown.nix** - Federation configuration

## Creating New Modules

### 1. Create Module File

Create your module in the appropriate category directory:

```bash
vim modules/services/category/servicename.nix
```

### 2. Follow Template Pattern

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
      # ... service-specific settings
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

### 3. Import in Category Default

Add to `modules/services/category/default.nix`:

```nix
{
  imports = [
    ./servicename.nix
    # ... other modules
  ];
}
```

### 4. Enable in Host Configuration

```nix
{
  modules.services.category.servicename.enable = true;
}
```

### 5. Test and Deploy

```bash
# Validate syntax
nix flake check

# Build without applying
sudo nixos-rebuild build --flake .

# Test without making bootable
sudo nixos-rebuild test --flake .

# Apply changes
sudo nixos-rebuild switch --flake .
```

## Common Patterns

### Enable with Defaults

```nix
{
  modules.services.media.jellyfin.enable = true;
}
```

### Enable with Custom Settings

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

### Conditional Configuration

```nix
{
  modules.services.media.jellyfin = {
    enable = true;
    # Caddy integration happens automatically if Caddy is enabled
  };
  
  modules.services.infrastructure.caddy.enable = true;
}
```

### Override Profile Defaults

```nix
{
  imports = [ ../../profiles/server.nix ];
  
  # Server profile enables many services
  # Disable specific ones you don't want
  modules.services.media.jellyseerr.enable = false;
}
```

## Troubleshooting

### Service Not Starting

1. Check if enabled: `grep -r "servicename.enable" hosts/`
2. Check module dependencies (e.g., Caddy needed for reverse proxy)
3. View service logs: `journalctl -u servicename -f`
4. Check service status: `systemctl status servicename`

### Module Errors

1. Validate syntax: `nix flake check`
2. Build without applying: `nixos-rebuild build --flake .`
3. Review error messages - they point to the specific module and line

### Port Conflicts

```bash
# Check if port is in use
sudo ss -tulpn | grep PORT

# Update port in module options
modules.services.category.servicename.port = 8081;
```

### Secrets Not Decrypting

1. Ensure SSH host key is correct in `secrets/secrets.nix`
2. Verify secret file exists: `ls secrets/`
3. Check agenix configuration: `cat modules/secrets.nix`
4. Test decryption: `nix develop --command agenix -d secrets/secretname.age`

## Additional Resources

- [Main README](../README.md) - Repository overview
- [Host Configurations](../hosts/README.md) - Per-host setup
- [Profiles](../profiles/README.md) - Role-based configurations
- [NixOS Module System](https://nixos.org/manual/nixos/stable/#sec-writing-modules) - Official docs
