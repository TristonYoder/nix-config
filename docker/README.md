# Docker Services

Docker Compose services managed with `compose2nix` for declarative container configuration.

## Table of Contents

- [Overview](#overview)
- [Usage](#usage)
- [Available Services](#available-services)
- [Managing Containers](#managing-containers)
- [Converting Compose Files](#converting-docker-compose-files)
- [Troubleshooting](#troubleshooting)

## Overview

Docker services are managed using NixOS's declarative container support via `compose2nix`, which converts Docker Compose files into NixOS configuration.

**Benefits:**
- Declarative container management
- Integration with NixOS module system
- Automatic startup and service management
- Version controlled configuration

## Usage

### Enable Docker Services

In your host configuration:

```nix
{
  imports = [
    # Core Docker
    ../docker/docker.nix
    ../docker/watchtower.nix
    
    # Media services
    ../docker/media/ersatztv.nix
    
    # Productivity
    ../docker/productivity/homarr.nix
  ];
}
```

### Enable Individual Containers

Each Docker service file provides enable options:

```nix
{
  # Enable the container
  virtualisation.arion.projects.homarr.enable = true;
}
```

Rebuild to apply:
```bash
sudo nixos-rebuild switch --flake .
```

## Available Services

### Core Services

#### docker.nix
- Docker daemon configuration
- Storage driver settings
- Network configuration
- User permissions

#### watchtower.nix
- Automatic container updates
- Monitors running containers
- Pulls latest images
- Configurable update schedule

### Media Services

- **audiobooks.nix** - Self-hosted audiobook server
- **ersatztv.nix** - Custom TV channels from your media
- **media-aq.nix** - Media acquisition and management automation

### Productivity Services

- **affine.nix** - Knowledge base (open source Notion alternative)
- **homarr.nix** - Homepage dashboard for services
- **outline.nix** - Team knowledge base with real-time collaboration
- **planning-poker.nix** - Agile estimation tool
- **tandoor.nix** - Recipe manager and meal planner

### Website Services

- **com.carolineyoder.nix** - Caroline Yoder's website
- **photography.carolineelizabeth.nix** - Photography portfolio
- **studio.7andco.nix** - Studio 7andco website

## Managing Containers

### View Running Containers

```bash
# List all containers
docker ps

# List all (including stopped)
docker ps -a
```

### View Logs

```bash
# Follow logs
docker logs -f container_name

# Last 100 lines
docker logs --tail 100 container_name

# Via systemd
journalctl -u arion-servicename -f
```

### Restart a Service

```bash
# Via systemctl (NixOS-managed, recommended)
sudo systemctl restart arion-homarr

# Or via Docker directly
docker restart container_name
```

### Update Containers

Watchtower handles automatic updates, but you can manually update:

```bash
# Pull latest images
docker compose pull

# Recreate containers
docker compose up -d

# Or rebuild from NixOS
sudo nixos-rebuild switch --flake .
```

### Check Container Status

```bash
# Via systemctl
systemctl status arion-servicename

# Via Docker
docker inspect container_name
```

## Converting Docker Compose Files

Original Docker Compose files are kept in `docker/dockercompose/` for reference.

### Regenerate Service from Compose File

```bash
cd docker/dockercompose

# Convert compose file to Nix
compose2nix \
  -inputs=docker-compose_service.yml \
  -output=../category/service.nix
```

### Add New Docker Service

1. Create or obtain Docker Compose file
2. Place in `docker/dockercompose/`
3. Convert to Nix with `compose2nix`
4. Import in host configuration
5. Enable the service

## Service Discovery

Services are accessed through:

- **Direct ports** - Configured in each service file
- **Caddy reverse proxy** - Set up in NixOS module configuration
- **Tailscale network** - For secure remote access

Example Caddy integration:
```nix
services.caddy.virtualHosts."homarr.example.com" = {
  extraConfig = ''
    reverse_proxy http://localhost:7575
  '';
};
```

## Data Persistence

Container data is stored in:

- `/var/lib/docker/volumes/` - Docker-managed volumes
- `/data/` - Custom mount points (defined per service)

**Backup important data regularly!**

## Networking

Most containers use:

- **Bridge network** - Default Docker network
- **Custom networks** - Defined in compose files for service isolation
- **Host network** - For services requiring host network access

## Security

1. **Secrets** - Use NixOS secret management (agenix) for sensitive data
2. **Updates** - Watchtower keeps containers updated automatically
3. **Isolation** - Containers run in isolated environments
4. **Firewall** - NixOS firewall controls external access
5. **User mapping** - Configure UID/GID mapping for proper permissions

## Troubleshooting

### Container Won't Start

```bash
# Check systemd logs
journalctl -u arion-servicename -xe

# Check Docker logs
docker logs container_name

# Verify compose configuration
docker compose config

# Check for errors in the generated Nix file
cat docker/category/service.nix
```

### Port Conflicts

```bash
# Check if port is already in use
sudo ss -tulpn | grep PORT

# Update port in service configuration
# Edit the .nix file or original compose file and regenerate
```

### Volume Permission Issues

```bash
# Check volume permissions
ls -la /var/lib/docker/volumes/volume_name/_data

# Fix permissions (adjust UID/GID as needed)
sudo chown -R 1000:1000 /data/service

# Some containers need specific UIDs
# Check service documentation
```

### Image Pull Failures

```bash
# Pull manually to see error
docker pull image:tag

# Check Docker Hub rate limits
docker pull --help

# Try different registry
# Edit compose file to use different source
```

### Container Networking Issues

```bash
# Inspect container network
docker network ls
docker network inspect network_name

# Check if container can reach other services
docker exec container_name ping other_service

# Restart Docker networking
sudo systemctl restart docker
```

## Why Docker Services?

These Docker services complement NixOS-native services in `modules/services/`. Use Docker for:

- Services not yet available in Nixpkgs
- Complex multi-container applications
- Services that update frequently
- Third-party applications without Nix packaging

Use NixOS modules for:
- Services with good Nix support
- Better integration with system configuration
- More declarative configuration

## Additional Resources

- [compose2nix](https://github.com/aksiksi/compose2nix) - Docker Compose to Nix converter
- [Docker Documentation](https://docs.docker.com/)
- [NixOS Containers](https://nixos.wiki/wiki/Docker)
- [Arion](https://docs.hercules-ci.com/arion/) - Docker Compose via Nix
- [Main README](../README.md) - Repository overview

---

**Services:** 10+ Docker services  
**Categories:** Core, Media, Productivity, Websites  
**Auto-Updates:** ✅ Via Watchtower
