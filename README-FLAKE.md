# David's NixOS Configuration - Flake Edition

This is a complete rewrite of the NixOS configuration using Nix flakes for better reproducibility and modularity.

## Structure

```
flake.nix                    # Main flake definition
├── modules/services/         # Service modules
│   ├── apps.nix             # Application services
│   ├── nas.nix              # NAS functionality
│   ├── caddy-hosts.nix      # Caddy virtual hosts
│   ├── github-actions.nix   # CI/CD configuration
│   ├── nextcloud.nix        # Nextcloud setup
│   ├── bitcoin.nix          # Bitcoin services (optional)
│   ├── wordpress.nix        # WordPress setup (optional)
│   ├── tailscale-router.nix  # Tailscale router (optional)
│   └── demos.nix            # Demo applications (optional)
├── docker/                   # Docker services (unchanged)
└── configuration.nix        # Main system configuration
```

## Key Improvements

### 1. **Reproducible Builds**
- All external dependencies are pinned to specific versions
- No more `fetchTarball` calls with hardcoded URLs
- Lock file ensures consistent builds across environments

### 2. **Modular Structure**
- Each service is now a separate module
- Easy to enable/disable services
- Better organization and maintainability

### 3. **Development Environments**
- `nix develop` for development shell
- `nix develop .#bitcoin` for Bitcoin development
- All dependencies managed by the flake

### 4. **Better Secret Management**
- API tokens and secrets can be managed through flake inputs
- More secure than hardcoded values

## Usage

### Building the System

```bash
# Build the system configuration
nix build .#nixosConfigurations.david.config.system.build.toplevel

# Or build and switch directly
sudo nixos-rebuild switch --flake .#david
```

### Development

```bash
# Enter development shell
nix develop

# Enter Bitcoin development shell
nix develop .#bitcoin
```

### Updating Dependencies

```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
```

## Service Modules

### Core Services (Always Enabled)
- **apps.nix**: Application services (Actual, Immich, Jellyfin, etc.)
- **nas.nix**: NAS functionality (ZFS, Syncthing, NFS, SMB)
- **caddy-hosts.nix**: Caddy virtual hosts for external services
- **github-actions.nix**: CI/CD configuration
- **nextcloud.nix**: Nextcloud file sharing

### Optional Services (Commented Out by Default)
- **bitcoin.nix**: Bitcoin services using nix-bitcoin
- **wordpress.nix**: WordPress content management
- **tailscale-router.nix**: Tailscale router container
- **demos.nix**: Demo applications for testing

## Enabling Optional Services

To enable optional services, uncomment the corresponding line in `flake.nix`:

```nix
# Optional services (commented out by default)
./modules/services/bitcoin.nix
./modules/services/wordpress.nix
./modules/services/tailscale-router.nix
./modules/services/demos.nix
```

## Migration from Old Configuration

The old configuration files have been converted to modules:

- `apps.nix` → `modules/services/apps.nix`
- `nas.nix` → `modules/services/nas.nix`
- `caddy-hosts.nix` → `modules/services/caddy-hosts.nix`
- `github-actions.nix` → `modules/services/github-actions.nix`
- `nextcloud.nix` → `modules/services/nextcloud.nix`

## Docker Services

Docker services remain unchanged and are still managed by docker-compose files. The `docker/` directory structure is preserved.

## Benefits

1. **Reproducible**: All dependencies are locked to specific versions
2. **Modular**: Easy to enable/disable services
3. **Maintainable**: Clear separation of concerns
4. **Development-friendly**: Built-in development environments
5. **Secure**: Better secret management
6. **Modern**: Uses latest Nix features

## Next Steps

1. Test the flake build: `nix flake check`
2. Deploy to system: `sudo nixos-rebuild switch --flake .#david`
3. Enable optional services as needed
4. Customize service configurations in respective modules

## Troubleshooting

If you encounter issues:

1. Check flake syntax: `nix flake check`
2. Update inputs: `nix flake update`
3. Check for conflicts in service configurations
4. Review logs: `journalctl -u <service-name>`

## Contributing

When adding new services:

1. Create a new module in `modules/services/`
2. Add the module to `flake.nix` imports
3. Document the service in this README
4. Test the configuration before committing
