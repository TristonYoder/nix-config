# Common Configuration Files

Shared configuration files that apply across all hosts, platforms, and users.

## Table of Contents

- [Overview](#overview)
- [Configuration Files](#configuration-files)
- [Usage](#usage)
- [Customization](#customization)
- [Best Practices](#best-practices)

## Overview

This directory contains base system-level configuration files that are imported by all hosts. These files establish the foundation for the entire nix-config setup, providing consistent system settings across different platforms (NixOS, Darwin) and environments (server, desktop, edge).

The common configurations are split by scope:
- **System-level**: Base system settings, packages, and programs
- **Platform-level**: OS-specific configurations (Linux/Darwin)

**Note:** User-level Home Manager configurations are in the `home/` directory, including `home/common.nix` for shared user settings.

## Configuration Files

### system.nix
**Base system configuration for all hosts**

Shared settings that apply to all machines regardless of platform.

**Includes:**
- Nix settings (flakes, experimental features, trusted users)
- Unfree packages allowance
- Timezone and locale defaults
- Common system packages (git, nano, wget, curl, htop, tree, etc.)
- Essential programs (zsh)

**Used by:** All NixOS and Darwin hosts

**Platform notes:**
- Some features (like i18n) are NixOS-only and configured in `linux.nix`
- Darwin-specific settings (like nix.optimise.automatic) are in profiles/darwin.nix

### linux.nix
**Common configuration for all Linux/NixOS hosts**

Settings shared across all NixOS machines.

**Includes:**
- Store optimization (auto-optimise-store)
- Locale settings (i18n)
- Linux-specific packages (pciutils, usbutils)
- Git system-wide enablement
- Sudo configuration

**Used by:** david, tristons-desk, pits (all NixOS hosts)

**Complements:** system.nix with Linux-specific settings

### darwin.nix
**Common configuration for all macOS/Darwin hosts**

Settings shared across all Darwin machines.

**Includes:**
- Darwin-specific system settings placeholder
- macOS-specific packages (if any)

**Used by:** tyoder-mbp (all Darwin hosts)

**Complements:** system.nix with macOS-specific settings

**Note:** Most Darwin configuration is in profiles/darwin.nix

## Usage

### In flake.nix

Common configurations are automatically imported for each host:

```nix
# For NixOS hosts
nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
  modules = [
    ./common/system.nix    # Base system
    ./common/linux.nix     # Linux-specific
    # ... other modules
  ];
};

# For Darwin hosts
darwinConfigurations.hostname = nix-darwin.lib.darwinSystem {
  modules = [
    ./common/system.nix    # Base system
    ./common/darwin.nix    # Darwin-specific
    # ... other modules
  ];
};
```

**Note:** For Home Manager configurations, see [home/README.md](../home/README.md).

## Customization

### Override Common Settings in Hosts

Host configurations can override common settings:

```nix
# In hosts/hostname/configuration.nix
{
  # Override timezone from common
  time.timeZone = lib.mkForce "America/New_York";
  
  # Add additional packages
  environment.systemPackages = with pkgs; [
    neovim
    tmux
  ];
}
```

## Best Practices

1. **Keep it minimal** - Only include settings truly common to all hosts/users
2. **Use lib.mkDefault** - Allow hosts to override without lib.mkForce
3. **Document platform differences** - Note when features are platform-specific
4. **Avoid host-specific settings** - Those belong in host configurations
5. **Test across platforms** - Changes affect all hosts

### When to Add Settings Here

**DO add to common/ if:**
- Setting applies to ALL hosts or users
- Setting is a sensible default that might be overridden
- Package/tool is universally useful

**DON'T add to common/ if:**
- Setting is host-specific
- Setting only applies to one platform (use linux.nix or darwin.nix)
- Setting is experimental or only for testing
- Package is specialized or rarely used

### Testing Changes

After modifying common configurations, test on multiple platforms:

```bash
# NixOS
sudo nixos-rebuild build --flake .

# Darwin
darwin-rebuild build --flake .

# Home Manager
home-manager build --flake .
```

Verify on at least one host per platform before committing.

## Common Patterns

### Adding a System Package

To add a package available to all systems:

```nix
# In common/system.nix
environment.systemPackages = with pkgs; [
  git
  nano
  wget
  your-new-package  # Add here
];
```

### Platform-Specific System Package

For Linux-only packages:

```nix
# In common/linux.nix
environment.systemPackages = with pkgs; [
  pciutils
  usbutils
  your-linux-package
];
```

For Darwin-only packages:

```nix
# In common/darwin.nix
environment.systemPackages = with pkgs; [
  your-macos-package
];
```

**Note:** For Home Manager package management, see [home/README.md](../home/README.md).

## File Relationships

```
common/
├── system.nix     → Imported by ALL hosts (NixOS & Darwin)
├── linux.nix      → Imported by NixOS hosts only (david, tristons-desk, pits)
└── darwin.nix     → Imported by Darwin hosts only (tyoder-mbp)
```

**Import hierarchy:**

```
Host Configuration (flake.nix)
├── common/system.nix (base)
├── common/linux.nix OR common/darwin.nix (platform)
├── profiles/*.nix (role)
└── hosts/*/configuration.nix (host-specific)
```

**Note:** Home Manager configurations have their own hierarchy in the `home/` directory.

## Additional Resources

- [Main README](../README.md) - Repository overview
- [Profiles](../profiles/README.md) - Role-based configurations
- [Modules](../modules/README.md) - Modular services and features
- [Hosts](../hosts/README.md) - Per-host configurations
- [Home Manager](../home/README.md) - User environment configuration

---

**Configuration Files:** 3 (system, linux, darwin)  
**Hosts Using These:** All (3 NixOS hosts: david, tristons-desk, pits; 1 Darwin host: tyoder-mbp)

