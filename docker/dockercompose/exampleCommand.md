# Docker Compose to Nix Conversion Guide

This guide shows how to convert docker-compose.yml files to NixOS modules using compose2nix and place them in the correct categorical directories.

## Navigation

```bash
cd ~/Projects/david-nixos/docker/dockercompose
```

## Directory Structure

After running compose2nix, files are organized into:
- `../media/` - Media-related services (streaming, photos, audiobooks)
- `../websites/` - Website containers (personal sites, portfolios)
- `../productivity/` - Productivity apps (notes, planning, recipes)

---

## Media Services

### Media Acquisition Stack
```bash
compose2nix -runtime docker -inputs docker-compose-media-aq.yml -output ../media/media-aq.nix
```

### Audiobooks
```bash
# Note: If you have a compose file for audiobooks, use:
# compose2nix -runtime docker -inputs docker-compose_audiobooks.yml -output ../media/audiobooks.nix
```

### ErsatzTV
```bash
# Note: If you have a compose file for ersatztv, use:
# compose2nix -runtime docker -inputs docker-compose_ersatztv.yml -output ../media/ersatztv.nix
```

### Damselfly (Photo Management)
```bash
compose2nix -runtime docker -inputs docker-compose_damselfly.yml -output ../media/damselfly.nix
```

---

## Productivity Services

### Affine (Notes & Collaboration)
```bash
cd affine
compose2nix -runtime docker -inputs docker-compose_affine.yml -output ../../productivity/affine.nix
cd ..
```

### Outline (Knowledge Base)
```bash
cd outline
compose2nix -runtime docker -inputs docker-compose_outline.yml -output ../../productivity/outline.nix --env_files=docker.env
cd ..
```

### Planning Poker
```bash
compose2nix -runtime docker -inputs docker-compose_planning-poker.yml -output ../productivity/planning-poker.nix
```

### Tandoor (Recipe Manager)
```bash
compose2nix -runtime docker -inputs docker-compose_tandoor.yml -output ../productivity/tandoor.nix
```

### Homarr (Dashboard)
```bash
compose2nix -runtime docker -inputs docker-compose_homarr.yml -output ../productivity/homarr.nix
```

### Wiki.JS (Documentation)
```bash
compose2nix -runtime docker -inputs docker-compose_wiki-js.yml -output ../productivity/wiki-js.nix
```

### Bookstack (Wiki)
```bash
compose2nix -runtime docker -inputs docker-compose_bookstack.yml -output ../productivity/bookstack.nix
```

### Docmost (Documentation)
```bash
compose2nix -runtime docker -inputs docker-compose_docmost.yml -output ../productivity/docmost.nix
```

---

## Website Services

### com.carolineyoder.com
```bash
compose2nix -runtime docker -inputs docker-compose_com_carolineyoder.yml -output ../websites/com.carolineyoder.nix
```

### Alternative Caroline Yoder Site
```bash
compose2nix -runtime docker -inputs docker-compose_com_carolineyoder2.yml -output ../websites/com.carolineyoder2.nix
```

### Photography Portfolio (carolineelizabeth.photography)
```bash
# Note: If you have a compose file for photography.carolineelizabeth, use:
# compose2nix -runtime docker -inputs docker-compose_photography.yml -output ../websites/photography.carolineelizabeth.nix
```

### 7andco Studio
```bash
# Note: If you have a compose file for studio.7andco, use:
# compose2nix -runtime docker -inputs docker-compose_studio.yml -output ../websites/studio.7andco.nix
```

### Code Server (Development)
```bash
compose2nix -runtime docker -inputs docker-compose_codeserver.yml -output ../websites/code-server.nix
```

---

## Other Services

### Caddy Reverse Proxy
```bash
compose2nix -runtime docker -inputs docker-compose_caddy.yml -output ../caddy.nix
```

### With Tailscale Integration
```bash
compose2nix -runtime docker -inputs docker-compose-with-ts.yml -output ../with-ts.nix
```

---

## After Conversion

1. **Add to flake.nix**: Include the new .nix file in the appropriate category imports
   ```nix
   # In flake.nix, under the correct category:
   ./docker/media/service-name.nix
   ./docker/websites/service-name.nix
   ./docker/productivity/service-name.nix
   ```

2. **Test the configuration**:
   ```bash
   sudo nixos-rebuild test --flake .#david
   ```

3. **Apply permanently**:
   ```bash
   sudo nixos-rebuild switch --flake .#david
   ```

---

## Quick Reference

**General pattern:**
```bash
compose2nix -runtime docker -inputs COMPOSE_FILE.yml -output ../CATEGORY/SERVICE-NAME.nix
```

**With environment files:**
```bash
compose2nix -runtime docker -inputs COMPOSE_FILE.yml -output ../CATEGORY/SERVICE-NAME.nix --env_files=.env
```

**Categories:**
- `media` - Streaming, photos, media acquisition
- `websites` - Website containers and portfolios  
- `productivity` - Apps, dashboards, documentation

---

## Troubleshooting

- **Missing compose file?** Some services may be custom-built or have their .nix files manually created
- **Wrong category?** Move the .nix file to the appropriate category folder and update flake.nix
- **Service won't start?** Check logs with `journalctl -u docker-SERVICE_NAME.service -f`
