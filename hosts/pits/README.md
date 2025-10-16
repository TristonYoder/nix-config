# pits - Pi in the Sky

Edge server configuration for public-facing services.

## Overview

**pits** is a lightweight edge server designed to run on a Raspberry Pi, VPS, or similar hardware with a public IP address. It serves as:
- **Public-facing edge node** with direct internet access
- **Reverse proxy** using Caddy to forward requests to internal services
- **VPN gateway** via Tailscale to securely connect to the main network
- **Lightweight entry point** optimized for minimal resource usage

## Specifications

- **Hostname**: pits
- **Profile**: edge (`profiles/edge.nix`)
- **Architecture**: aarch64-linux (Raspberry Pi) or x86_64-linux (VPS) - configurable in `flake.nix`
- **User**: tristonyoder
- **Services**: Caddy, Tailscale, vscode-server
- **Resource Requirements**: 1GB+ RAM, 20GB+ disk

## Quick Setup

### Option 1: Single Command Bootstrap (VPS)

For a fresh NixOS VPS:

```bash
# Enable SSH first (via VPS console)
sudo systemctl enable --now sshd && sudo passwd root

# Then from your local machine
ssh root@<VPS_IP> 'nix-shell -p git --run "git clone https://github.com/TristonYoder/david-nixos.git /tmp/nixos-config && cd /tmp/nixos-config && sudo nixos-generate-config --show-hardware-config > hosts/pits/hardware-configuration.nix && sudo mv /tmp/nixos-config /etc/nixos && cd /etc/nixos && sudo nixos-rebuild switch --flake .#pits"'
```

### Option 2: Remote Deployment

```bash
# Get hardware config from VPS
ssh root@<VPS_IP> nixos-generate-config --show-hardware-config > hosts/pits/hardware-configuration.nix

# Commit it
git add hosts/pits/hardware-configuration.nix
git commit -m "Add pits hardware config"

# Deploy (builds locally, faster)
nixos-rebuild switch --flake .#pits \
  --target-host root@<VPS_IP> \
  --build-host localhost
```

### Option 3: Raspberry Pi Installation

1. Download NixOS ARM image: https://nixos.org/download.html#nixos-iso
2. Flash to SD card
3. Boot and enable SSH
4. Deploy using Option 2 above

## Post-Setup Configuration

### Configure Tailscale

```bash
ssh root@<VPS_IP>
sudo tailscale up
```

### Add Reverse Proxies

Edit `hosts/pits/configuration.nix`:

```nix
services.caddy.virtualHosts."app.example.com" = {
  extraConfig = ''
    reverse_proxy http://david:8080  # Via Tailscale
  '';
};
```

Rebuild:
```bash
sudo nixos-rebuild switch --flake .#pits
```

### Point DNS to Server

In your DNS provider, add A records:
```
A    app.example.com    <VPS_IP>
```

Caddy automatically handles HTTPS certificates.

## Daily Operations

### Update System

```bash
ssh tristonyoder@<VPS_IP>
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#pits
```

### Monitor Services

```bash
# Check status
systemctl status caddy tailscaled

# View logs
journalctl -u caddy -f
journalctl -u tailscaled -f

# Resource usage
htop
```

### Clean Up Disk Space

```bash
sudo nix-collect-garbage -d
```

## Configuration

### Enabled Services

- ✅ Caddy (reverse proxy)
- ✅ Tailscale (VPN)
- ✅ vscode-server (remote development)
- ✅ OpenSSH (hardened)

### Firewall

Open ports: 22 (SSH), 80 (HTTP), 443 (HTTPS)

### Optimizations

The edge profile includes:
- Reduced journal size (50MB system, 25MB runtime)
- Aggressive garbage collection (daily, keeps 7 days)
- zram swap (50% of RAM)
- No desktop environment

## Troubleshooting

**Can't SSH:**
- Check VPS console in provider dashboard
- Verify firewall: `iptables -L`
- Check SSH: `systemctl status sshd`

**Caddy certificate issues:**
- Verify DNS: `dig app.example.com +short`
- Check logs: `journalctl -u caddy -f`
- Ensure ports 80/443 are open

**Can't reach internal services:**
- Check Tailscale: `tailscale status`
- Test connectivity: `tailscale ping david`
- Verify service is running internally

**Out of disk space:**
```bash
sudo nix-collect-garbage -d
sudo nix-store --optimize
```

## VPS Providers

**Recommended specs**: 1-2 CPU cores, 2GB RAM, 25GB disk (~$5-15/month)

- **Hetzner Cloud**: €3.79/mo (best value)
- **Vultr**: $5/mo
- **DigitalOcean**: $6/mo
- **Linode**: $5/mo

## Architecture

Default: `aarch64-linux` (Raspberry Pi)

For x86_64 VPS, edit `flake.nix`:
```nix
system = "x86_64-linux";  # Change from aarch64-linux
```

