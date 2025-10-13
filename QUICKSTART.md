# Quick Start Guide - Multi-Host NixOS Configuration

## 🚀 Quick Commands

### On NixOS (david or tristons-desk)
```bash
# Test configuration
sudo nixos-rebuild test --flake .

# Apply configuration
sudo nixos-rebuild switch --flake .

# Build without applying
sudo nixos-rebuild build --flake .
```

### On macOS (tyoder-mbp)
```bash
# First time setup (if nix-darwin not installed)
nix run nix-darwin -- switch --flake ~/Projects/david-nixos

# Regular rebuild
darwin-rebuild switch --flake .

# Test without applying
darwin-rebuild build --flake .
```

## 📁 Quick Reference

### Where Things Are

| Component | Location |
|-----------|----------|
| Common settings | `common.nix` |
| Server profile | `profiles/server.nix` |
| Desktop profile | `profiles/desktop.nix` |
| macOS profile | `profiles/darwin.nix` |
| Host configs | `hosts/<hostname>/configuration.nix` |
| Hardware configs | `hosts/<hostname>/hardware-configuration.nix` |
| Home Manager | `home/<username>.nix` |
| Shared home config | `home/common.nix` |
| System modules | `modules/` |
| Docker services | `docker/` |

### Hosts

| Hostname | Type | Profile | User |
|----------|------|---------|------|
| `david` | NixOS Server | server | tristonyoder |
| `tristons-desk` | NixOS Desktop | desktop | tristonyoder |
| `tyoder-mbp` | macOS | darwin | tyoder |

## 🔧 Common Tasks

### Update Flake Inputs
```bash
nix flake update
```

### Add a Package (Home Manager)
Edit `home/<username>.nix`:
```nix
home.packages = with pkgs; [
  # Add your package here
  neofetch
];
```

### Enable a Service (NixOS)
Edit `hosts/<hostname>/configuration.nix`:
```nix
modules.services.media.jellyfin.enable = true;
```

### Edit Secrets
```bash
nix develop  # Enter dev shell with agenix
agenix -e secretname.age
```

### Check Configuration
```bash
nix flake check
nix flake show
```

## 🐛 Troubleshooting

### "cannot find module" error
```bash
nix flake update
```

### macOS settings not applying
```bash
killall Dock && killall Finder
# Or log out and back in
```

### NixOS hardware config needed
```bash
# On the target machine
sudo nixos-generate-config --show-hardware-config
# Copy output to hosts/<hostname>/hardware-configuration.nix
```

## 📚 Documentation

- Full guide: `MULTI-HOST-SETUP.md`
- Implementation details: `IMPLEMENTATION-SUMMARY.md`
- Module system: `MODULAR-STRUCTURE.md`
- Secrets: `secrets/README.md`

## 🎯 Shell Aliases (configured)

```bash
rebuild          # NixOS rebuild with auto-detection
rebuild-darwin   # macOS rebuild
rebuild-home     # Home Manager only
hms              # Quick darwin rebuild
```

## ⚡ Tips

1. **Hostname auto-detection**: You don't need to specify `#hostname` if your system hostname matches the config name
2. **Test first**: Always run `test` or `build` before `switch` on production systems
3. **Rollback**: NixOS/nix-darwin support rollbacks if something breaks
4. **Flake lock**: Commit `flake.lock` to track exact versions

---
**Need help?** Check `MULTI-HOST-SETUP.md` for detailed information.

