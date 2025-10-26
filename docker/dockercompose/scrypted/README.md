# Scrypted Docker Configuration

This directory contains the Docker configuration for Scrypted, a home automation platform that provides a unified interface for various smart home devices and protocols.

## Files

- `docker-compose_scrypted.yml` - Original Docker Compose configuration
- `scrypted.env` - Environment variables template
- `../scrypted.nix` - Generated NixOS configuration

## Setup

### 1. Generate Watchtower Token

Generate a secure token for Watchtower auto-updates:

```bash
openssl rand -hex 32
```

### 2. Encrypt the Secret

Add the token to the encrypted secret file:

```bash
echo "WATCHTOWER_HTTP_API_TOKEN=your_generated_token_here" | sudo agenix -e secrets/scrypted-watchtower-token.age
```

### 3. Enable the Service

Add to your host configuration (e.g., `hosts/david/configuration.nix`):

```nix
imports = [ ../../docker/scrypted.nix ];

# Enable Scrypted
virtualisation.arion.projects.scrypted.enable = true;
```

### 4. Apply Configuration

```bash
sudo nixos-rebuild switch --flake .
```

## Features

- **Scrypted Core**: Main application container with host networking
- **Watchtower**: Automatic updates with HTTP API integration
- **Device Access**: USB and DRI device passthrough for hardware acceleration
- **Volume Persistence**: Data stored in `/var/lib/scrypted/volume`
- **Secret Management**: Watchtower token managed via age encryption

## Network Configuration

Both containers use host networking for maximum compatibility with:
- HomeKit integration
- Device discovery protocols
- Local network access

## Device Access

The configuration includes access to:
- `/dev/bus/usb` - USB devices (Coral TPU, Z-Wave adapters, etc.)
- `/dev/dri` - Direct Rendering Infrastructure (hardware video decoding)

## Logging

- Scrypted: Logging disabled to reduce wear on storage
- Watchtower: Uses journald for system integration

## Updates

Watchtower automatically updates Scrypted every hour and cleans up old images.

## Troubleshooting

1. **Permission Issues**: Ensure the `/var/lib/scrypted/volume` directory exists and has proper permissions
2. **Device Access**: Verify USB devices are accessible and not in use by other processes
3. **Network Issues**: Check that host networking is working and no firewall blocks local traffic
