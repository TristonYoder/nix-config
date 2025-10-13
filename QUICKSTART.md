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
| `pits` | NixOS Edge (Pi) | edge | tristonyoder |
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

- **[Main README](README.md)** - Complete overview and features
- **[Hosts](hosts/README.md)** - Multi-host setup guide
- **[Modules](modules/README.md)** - Module system and services
- **[Home Manager](home/README.md)** - User environment configuration
- **[GitHub Actions](.github/workflows/README.md)** - CI/CD automation
- **[Secrets](secrets/README.md)** - Secret management

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

## 🔗 Quick Links

- **Add a new host:** See [hosts/README.md](hosts/README.md)
- **Enable a service:** See [modules/README.md](modules/README.md)
- **Setup CI/CD:** See [.github/workflows/README.md](.github/workflows/README.md)
- **Manage secrets:** See [secrets/README.md](secrets/README.md)

---
**Need detailed help?** Check the [main README](README.md) or directory-specific READMEs.

