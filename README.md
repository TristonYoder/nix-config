# Multi-Host NixOS & Darwin Configuration

> A unified flake-based configuration managing NixOS servers, NixOS desktops, and macOS machines with integrated Home Manager.

## 🌟 Features

- **Multi-Host Support**: Manage NixOS and macOS machines from a single repository
- **Hostname Auto-Detection**: No need to specify host in rebuild commands
- **Home Manager Integration**: Unified user environment across all platforms
- **Profile-Based**: Role-based configurations (server, desktop, darwin)
- **Modular Services**: Enable/disable services with simple flags
- **Secret Management**: Encrypted secrets with agenix
- **macOS Native**: Full nix-darwin support with Homebrew & Mac App Store integration

## 📋 Managed Hosts

| Host | Type | Profile | Services |
|------|------|---------|----------|
| **david** | NixOS Server | Server | Infrastructure, Media, Productivity, Storage |
| **tristons-desk** | NixOS Desktop | Desktop | Minimal workstation setup |
| **tyoder-mbp** | macOS (M1) | Darwin | Development tools, GUI apps via Homebrew |

## 🚀 Quick Start

### On NixOS
```bash
sudo nixos-rebuild switch --flake .
```

### On macOS
```bash
# First time
nix run nix-darwin -- switch --flake ~/Projects/david-nixos

# Subsequent rebuilds
darwin-rebuild switch --flake .
```

## 📁 Repository Structure

```
.
├── flake.nix              # Main flake with all host configurations
├── common.nix             # Shared settings across all hosts
├── profiles/              # Role-based configurations
│   ├── server.nix
│   ├── desktop.nix
│   └── darwin.nix
├── hosts/                 # Per-host configurations
│   ├── david/
│   ├── tristons-desk/
│   └── tyoder-mbp/
├── home/                  # Home Manager configurations
│   ├── common.nix         # Shared user settings
│   ├── tyoder.nix         # macOS user
│   └── tristonyoder.nix   # NixOS user
├── modules/               # System modules
├── docker/                # Docker service definitions
└── secrets/               # Encrypted secrets (agenix)
```

## 📚 Documentation

### Getting Started
- **[QUICKSTART.md](QUICKSTART.md)** - Commands and quick reference
- **[MULTI-HOST-SETUP.md](MULTI-HOST-SETUP.md)** - Complete setup guide
- **[IMPLEMENTATION-SUMMARY.md](IMPLEMENTATION-SUMMARY.md)** - What was implemented

### Technical Details
- **[MODULAR-STRUCTURE.md](MODULAR-STRUCTURE.md)** - Module system documentation
- **[secrets/README.md](secrets/README.md)** - Secret management guide
- **[README-FLAKE.md](README-FLAKE.md)** - Original flake documentation
- **[README-GitHub-Actions.md](README-GitHub-Actions.md)** - CI/CD setup

## 🛠️ Common Commands

```bash
# Rebuild current system (auto-detects hostname)
sudo nixos-rebuild switch --flake .      # NixOS
darwin-rebuild switch --flake .          # macOS

# Test before applying
sudo nixos-rebuild test --flake .
darwin-rebuild build --flake .

# Update all flake inputs
nix flake update

# Enter development shell
nix develop

# Check configuration
nix flake check
nix flake show
```

## 🎯 Configuration Examples

### Enable a Service (NixOS)
Edit `hosts/<hostname>/configuration.nix`:
```nix
# Already enabled by profile, but can override
modules.services.media.jellyfin.enable = true;
```

### Add Packages (Home Manager)
Edit `home/<username>.nix`:
```nix
home.packages = with pkgs; [
  neofetch
  htop
];
```

### Add macOS Apps
Edit `home/tyoder.nix`:
```nix
homebrew.casks = [
  "firefox"
  "visual-studio-code"
];

mas.apps = [
  { id = "441258766"; name = "Magnet"; }
];
```

## 🔐 Security

- Secrets managed with **agenix** (age encryption)
- SSH keys for host and user authentication
- No plaintext secrets in repository
- `.gitignore` configured to protect sensitive data

## 📦 What's Included

### NixOS Server (david)
✅ Caddy reverse proxy  
✅ PostgreSQL database  
✅ Jellyfin media server  
✅ Immich photo management  
✅ Vaultwarden password manager  
✅ ZFS storage  
✅ Samba/NFS file sharing  
✅ And many more services...

### NixOS Desktop (tristons-desk)
✅ KDE Plasma desktop  
✅ Development tools (VSCode, git)  
✅ Tailscale VPN  
✅ Minimal service footprint  

### macOS (tyoder-mbp)
✅ Homebrew package management  
✅ Mac App Store integration  
✅ System defaults (Dock, Finder, etc.)  
✅ Development environment  
✅ Zsh with Oh My Zsh & Powerlevel10k  

## 🔄 Adding a New Host

1. Create directory: `mkdir -p hosts/new-hostname`
2. Add configuration: `hosts/new-hostname/configuration.nix`
3. Generate hardware config (NixOS only)
4. Add to `flake.nix` in `nixosConfigurations` or `darwinConfigurations`
5. Rebuild: `sudo nixos-rebuild switch --flake .`

See [MULTI-HOST-SETUP.md](MULTI-HOST-SETUP.md) for detailed instructions.

## 🤝 Contributing

This is a personal configuration repository, but feel free to use it as a reference for your own setup!

When making changes:
1. Test with `nixos-rebuild test` or `darwin-rebuild build`
2. Check flake: `nix flake check`
3. Document significant changes
4. Update relevant documentation files

## 📞 Support & Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [agenix](https://github.com/ryantm/agenix)

## 🎉 Status

✅ **Multi-host configuration active**  
✅ **3 hosts configured** (david, tristons-desk, tyoder-mbp)  
✅ **Home Manager integrated**  
✅ **Auto-detection enabled**  
✅ **Documentation complete**  

---

**Last Updated**: October 13, 2025  
**Flake Compatible**: NixOS 25.05+ / nix-darwin latest

