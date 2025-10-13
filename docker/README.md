# Docker Services

Docker Compose services managed with `compose2nix` for declarative container configuration.

## Structure

```
docker/
├── docker.nix           # Core Docker daemon configuration
├── watchtower.nix       # Automatic container updates
├── media/               # Media-related containers
│   ├── audiobooks.nix
│   ├── ersatztv.nix
│   └── media-aq.nix
├── productivity/        # Productivity applications
│   ├── affine.nix
│   ├── homarr.nix
│   ├── outline.nix
│   ├── planning-poker.nix
│   └── tandoor.nix
└── websites/            # Website containers
    ├── com.carolineyoder.nix
    ├── photography.carolineelizabeth.nix
    └── studio.7andco.nix
```

## Overview

These services are managed using NixOS's declarative container support via `compose2nix`, which converts Docker Compose files into NixOS configuration.

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
  virtualisation.arion.projects.homarr.enable = true;
}
```

## Core Services

### docker.nix

Core Docker daemon configuration:
- Docker package installation
- Storage driver configuration
- Network settings
- User permissions

### watchtower.nix

Automatic container updates:
- Monitors running containers
- Pulls latest images
- Restarts containers with updates
- Configurable schedule

## Media Services

### audiobooks.nix
Self-hosted audiobook server with web player.

### ersatztv.nix
Create custom TV channels from your media.

### media-aq.nix
Media acquisition and management automation.

## Productivity Services

### affine.nix
Knowledge base and project management (open source Notion alternative).

### homarr.nix
Homepage dashboard for services and applications.

### outline.nix
Team knowledge base with real-time collaboration.

### planning-poker.nix
Agile estimation and planning tool.

### tandoor.nix
Recipe manager and meal planner.

## Website Services

### com.carolineyoder.nix
Caroline Yoder's website container.

### photography.carolineelizabeth.nix
Photography portfolio website.

### studio.7andco.nix
Studio 7andco website.

## Converting Docker Compose Files

To regenerate a service from a Docker Compose file:

```bash
cd docker/dockercompose

# Convert compose file to Nix
compose2nix \
  -inputs=docker-compose_service.yml \
  -output=../category/service.nix
```

## Docker Compose Files

Original Docker Compose files are kept in `docker/dockercompose/` for reference and regeneration:

```
dockercompose/
├── docker-compose_bookstack.yml
├── docker-compose_caddy.yml
├── docker-compose_homarr.yml
├── docker-compose_tandoor.yml
└── ...
```

## Service Discovery

Services are typically accessed through:
- **Direct ports:** Configured in each service file
- **Caddy reverse proxy:** Set up in NixOS module configuration
- **Tailscale network:** For secure remote access

## Managing Containers

### View Running Containers

```bash
docker ps
```

### View Logs

```bash
docker logs -f container_name
```

### Restart a Service

```bash
# Via systemctl (NixOS-managed)
sudo systemctl restart arion-homarr

# Or via Docker
docker restart container_name
```

### Update Containers

Watchtower handles automatic updates, but you can manually update:

```bash
docker compose pull
docker compose up -d
```

## Data Persistence

Container data is typically stored in:
- `/var/lib/docker/volumes/` - Docker-managed volumes
- `/data/` - Custom mount points (defined per service)

## Networking

Most containers use:
- **Bridge network:** Default Docker network
- **Custom networks:** Defined in compose files
- **Host network:** For services requiring host network access

## Security Considerations

1. **Secrets:** Use NixOS secret management (agenix) for sensitive data
2. **Updates:** Watchtower keeps containers updated
3. **Isolation:** Containers run in isolated environments
4. **Firewall:** NixOS firewall controls external access

## Troubleshooting

### Container Won't Start

```bash
# Check logs
journalctl -u arion-servicename -xe

# Check Docker logs
docker logs container_name

# Verify configuration
docker compose config
```

### Port Conflicts

Check if port is already in use:

```bash
sudo ss -tulpn | grep PORT
```

### Volume Permissions

Ensure correct permissions on mounted volumes:

```bash
sudo chown -R 1000:1000 /data/service
```

## Resources

- [compose2nix](https://github.com/aksiksi/compose2nix) - Docker Compose to Nix converter
- [Docker Documentation](https://docs.docker.com/)
- [NixOS Containers](https://nixos.wiki/wiki/Docker)

---

**Note:** These Docker services complement the NixOS-native services defined in `modules/services/`. Use Docker for services not yet available in Nixpkgs.

