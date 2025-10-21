# Docker Compose Files

Original Docker Compose files used as sources for generating NixOS modules via `compose2nix`.

## Purpose

These files are kept for:
- **Reference** - Original compose configuration
- **Regeneration** - Source for updating service modules
- **Documentation** - Service requirements and dependencies

## Converting to Nix

### Basic Pattern

```bash
compose2nix \
  -runtime docker \
  -inputs COMPOSE_FILE.yml \
  -output ../CATEGORY/SERVICE-NAME.nix
```

### With Environment Files

```bash
compose2nix \
  -runtime docker \
  -inputs COMPOSE_FILE.yml \
  -output ../CATEGORY/SERVICE-NAME.nix \
  --env_files=.env
```

### With Subdirectories

```bash
cd subdirectory
compose2nix \
  -runtime docker \
  -inputs docker-compose.yml \
  -output ../../CATEGORY/SERVICE-NAME.nix \
  --env_files=docker.env
cd ..
```

## Output Categories

- `../media/` - Media services (streaming, photos, audiobooks)
- `../websites/` - Website containers
- `../productivity/` - Productivity apps (notes, planning, recipes)

## Example Conversions

### Media Services

```bash
compose2nix -runtime docker \
  -inputs docker-compose-media-aq.yml \
  -output ../media/media-aq.nix
```

### Productivity

```bash
compose2nix -runtime docker \
  -inputs docker-compose_homarr.yml \
  -output ../productivity/homarr.nix

compose2nix -runtime docker \
  -inputs docker-compose_tandoor.yml \
  -output ../productivity/tandoor.nix
```

### Services with Environment Files

```bash
cd outline
compose2nix -runtime docker \
  -inputs docker-compose_outline.yml \
  -output ../../productivity/outline.nix \
  --env_files=docker.env
cd ..
```

## After Conversion

1. Review the generated .nix file
2. Import in host configuration
3. Enable the service
4. Rebuild

```bash
# Import in hosts/david/configuration.nix
imports = [ ../../docker/productivity/homarr.nix ];

# Enable
virtualisation.arion.projects.homarr.enable = true;

# Apply
sudo nixos-rebuild switch --flake .
```

## Updating Services

When updating a Docker service:

1. Edit the compose file here
2. Regenerate the .nix file with compose2nix
3. Test and rebuild

## Additional Resources

- [compose2nix](https://github.com/aksiksi/compose2nix)
- [Docker README](../README.md) - Service management
- [Main README](../../README.md) - Repository overview

---

**Purpose:** Source files for compose2nix conversions  
**Status:** Reference and regeneration
