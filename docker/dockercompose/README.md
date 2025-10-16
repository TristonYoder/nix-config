# Docker Compose Services

This directory contains docker-compose.yml files for various services. Use compose2nix to convert them to NixOS modules.

## Quick Reference

```bash
# General pattern
compose2nix -runtime docker -inputs COMPOSE_FILE.yml -output ../CATEGORY/SERVICE-NAME.nix

# With environment files
compose2nix -runtime docker -inputs COMPOSE_FILE.yml -output ../CATEGORY/SERVICE-NAME.nix --env_files=.env
```

## Categories

- `../media/` - Media services (streaming, photos, audiobooks)
- `../websites/` - Website containers
- `../productivity/` - Productivity apps (notes, planning, recipes)

## Examples

### Media Services

```bash
compose2nix -runtime docker -inputs docker-compose-media-aq.yml -output ../media/media-aq.nix
compose2nix -runtime docker -inputs docker-compose_damselfly.yml -output ../media/damselfly.nix
```

### Productivity

```bash
# Services with subdirectories
cd affine && compose2nix -runtime docker -inputs docker-compose_affine.yml -output ../../productivity/affine.nix && cd ..
cd outline && compose2nix -runtime docker -inputs docker-compose_outline.yml -output ../../productivity/outline.nix --env_files=docker.env && cd ..

# Direct conversions
compose2nix -runtime docker -inputs docker-compose_planning-poker.yml -output ../productivity/planning-poker.nix
compose2nix -runtime docker -inputs docker-compose_tandoor.yml -output ../productivity/tandoor.nix
compose2nix -runtime docker -inputs docker-compose_homarr.yml -output ../productivity/homarr.nix
compose2nix -runtime docker -inputs docker-compose_wiki-js.yml -output ../productivity/wiki-js.nix
compose2nix -runtime docker -inputs docker-compose_bookstack.yml -output ../productivity/bookstack.nix
compose2nix -runtime docker -inputs docker-compose_docmost.yml -output ../productivity/docmost.nix
```

### Websites

```bash
compose2nix -runtime docker -inputs docker-compose_com_carolineyoder.yml -output ../websites/com.carolineyoder.nix
compose2nix -runtime docker -inputs docker-compose_com_carolineyoder2.yml -output ../websites/com.carolineyoder2.nix
compose2nix -runtime docker -inputs docker-compose_codeserver.yml -output ../websites/code-server.nix
```

## After Conversion

Add the service to your NixOS configuration and rebuild:

```bash
sudo nixos-rebuild switch --flake .#david
```
