# Installing NixOS on pits (Pi in the Sky)

Complete guide for setting up the pits edge server on a cloud VPS (AWS, GCloud, Vultr, DigitalOcean, etc.)

## Overview

**pits** is a lightweight edge server with a public IP, designed to run:
- **Caddy** as a reverse proxy for your services
- **Tailscale** for secure VPN access to internal infrastructure
- Minimal resource footprint optimized for low-cost VPS instances

## Prerequisites

- Cloud VPS with NixOS support (or ability to install NixOS)
- SSH access to the server
- Public IP address
- 1GB+ RAM, 20GB+ disk recommended
- Root or sudo access

## Part 1: Get a NixOS VPS

### Option A: Providers with Native NixOS Support

**Hetzner Cloud** (Recommended - native NixOS support)
```bash
# Create a server with NixOS from their dashboard
# Select: NixOS 23.11 or latest
# Size: CX11 or larger (2GB RAM recommended)
```

**Vultr**
- Offers NixOS in their OS templates
- Choose "NixOS" when creating instance

**DigitalOcean**
- No native NixOS support, use Option B

### Option B: Install NixOS on Any VPS

If your provider doesn't offer NixOS, use [nixos-anywhere](https://github.com/nix-community/nixos-anywhere):

```bash
# From your local machine
nix run github:nix-community/nixos-anywhere -- --flake .#pits root@<VPS_IP>
```

Or use the [NixOS Infect](https://github.com/elitak/nixos-infect) script on the running server.

## Part 2: Initial Access

### Step 1: SSH into the VPS

```bash
# Initial SSH (use password or key from VPS provider)
ssh root@<VPS_PUBLIC_IP>
```

### Step 2: Set Up SSH Keys (if not already configured)

```bash
# On your local machine, copy your SSH key
ssh-copy-id root@<VPS_PUBLIC_IP>

# Test key-based login
ssh root@<VPS_PUBLIC_IP>
```

## Part 3: Deploy Your Configuration

### Method 1: Clone and Build on the Server (Recommended for First Install)

```bash
# SSH into the VPS
ssh root@<VPS_PUBLIC_IP>

# Install git temporarily
nix-shell -p git

# Clone your repository
git clone https://github.com/TristonYoder/david-nixos.git /etc/nixos
cd /etc/nixos

# Generate hardware configuration
sudo nixos-generate-config --show-hardware-config > hosts/pits/hardware-configuration.nix

# Review the hardware config
cat hosts/pits/hardware-configuration.nix

# Edit the pits configuration for your specific setup
nano hosts/pits/configuration.nix

# Configure your public IP (if static)
# networking.interfaces.ens3.ipv4.addresses = [{
#   address = "YOUR_PUBLIC_IP";
#   prefixLength = 24;
# }];

# Build and switch to the new configuration
sudo nixos-rebuild switch --flake .#pits

# Reboot to ensure everything works
sudo reboot
```

### Method 2: Deploy Remotely from Your Mac

```bash
# On your local machine (tyoder-mbp)
cd ~/Projects/david-nixos

# Get the hardware config from the VPS
ssh root@<VPS_IP> nixos-generate-config --show-hardware-config > hosts/pits/hardware-configuration.nix

# Review and adjust if needed
cat hosts/pits/hardware-configuration.nix

# Commit the hardware config
git add hosts/pits/hardware-configuration.nix
git commit -m "feat: Add hardware config for pits cloud VPS"
git push

# Deploy remotely (builds on your Mac, copies to VPS)
nixos-rebuild switch --flake .#pits \
  --target-host root@<VPS_IP> \
  --build-host localhost

# Or build on the VPS (slower but uses VPS resources):
nixos-rebuild switch --flake .#pits --target-host root@<VPS_IP>
```

## Part 4: Configure Your Edge Server

### Step 1: Set Up Networking

```bash
# SSH back into pits
ssh root@<VPS_IP>

# Edit configuration to set static IP or configure network
sudo nano /etc/nixos/hosts/pits/configuration.nix
```

**For static IP** (uncomment and adjust in configuration.nix):
```nix
networking.interfaces.eth0.ipv4.addresses = [{
  address = "YOUR_PUBLIC_IP";
  prefixLength = 24;
}];
networking.defaultGateway = "YOUR_GATEWAY";
networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
```

**For DHCP** (default, should already work):
```nix
networking.useDHCP = true;
```

### Step 2: Configure Firewall

The edge profile already opens ports 22, 80, 443. Adjust if needed:

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 80 443 ];
  # Add more ports as needed
};
```

### Step 3: Set Up Caddy Reverse Proxy

Edit `/etc/nixos/hosts/pits/configuration.nix`:

```nix
# Example: Proxy to internal service via Tailscale
services.caddy.virtualHosts."app.yourdomain.com" = {
  extraConfig = ''
    reverse_proxy http://david.tailscale:8080
  '';
};

# Example: Proxy to external service
services.caddy.virtualHosts."service.yourdomain.com" = {
  extraConfig = ''
    reverse_proxy http://192.168.1.100:3000
  '';
};
```

Rebuild after changes:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#pits
```

### Step 4: Configure Tailscale

```bash
# Authenticate with Tailscale
sudo tailscale up

# Check status
tailscale status

# You should now see pits in your Tailscale network
# And it can reach your internal servers (like david)
```

### Step 5: Create User Account

```bash
# Set password for tristonyoder
sudo passwd tristonyoder

# Test SSH with user account
# From another terminal:
ssh tristonyoder@<VPS_IP>
```

## Part 5: DNS and Domain Configuration

### Point Your Domain to the VPS

In your DNS provider (Cloudflare, etc.):

```
A    @                  YOUR_VPS_PUBLIC_IP
A    *.yourdomain.com   YOUR_VPS_PUBLIC_IP
```

Or specific subdomains:
```
A    app.yourdomain.com     YOUR_VPS_PUBLIC_IP
A    service.yourdomain.com YOUR_VPS_PUBLIC_IP
```

### Test DNS Propagation

```bash
# From your local machine
dig app.yourdomain.com +short
# Should return your VPS IP

# Test HTTP
curl http://app.yourdomain.com
```

### Enable HTTPS with Caddy

Caddy automatically handles Let's Encrypt certificates. Just use `https://` in your config:

```nix
services.caddy.virtualHosts."app.yourdomain.com" = {
  extraConfig = ''
    reverse_proxy http://internal-server:8080
  '';
};
```

Caddy will automatically get a certificate for `app.yourdomain.com`!

## Part 6: Security Hardening

### Disable Password Authentication

Edit `/etc/nixos/hosts/pits/configuration.nix`:

```nix
services.openssh.settings = {
  PermitRootLogin = "prohibit-password";  # Or "no" to disable completely
  PasswordAuthentication = false;
};
```

Rebuild:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#pits
```

### Set Up Fail2ban (Optional)

Add to pits configuration:
```nix
services.fail2ban = {
  enable = true;
  maxretry = 5;
  bantime = "10m";
};
```

### Enable Automatic Security Updates

Edit `/etc/nixos/hosts/pits/configuration.nix`:

```nix
system.autoUpgrade = {
  enable = true;
  allowReboot = false;  # Set to true for automatic reboots
  dates = "daily";
  flake = "github:TristonYoder/david-nixos#pits";
};
```

## Part 7: Monitoring and Maintenance

### Check System Status

```bash
# SSH into pits
ssh tristonyoder@<VPS_IP>

# Check services
systemctl status caddy
systemctl status tailscaled

# Check resource usage
htop

# Check disk space
df -h

# View logs
journalctl -f
```

### Update Configuration

```bash
# Pull latest changes
cd /etc/nixos
git pull

# Rebuild
sudo nixos-rebuild switch --flake .#pits
```

### Rollback if Needed

```bash
# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous
sudo nixos-rebuild switch --rollback
```

## Troubleshooting

### Can't SSH After Rebuild

1. Check VPS console in provider's dashboard
2. Verify firewall: `sudo iptables -L`
3. Check SSH service: `systemctl status sshd`
4. Rollback if needed via console

### Caddy Not Getting Certificates

1. Verify DNS points to VPS: `dig yourdomain.com +short`
2. Check port 80/443 are open: `sudo ss -tlnp | grep :80`
3. View Caddy logs: `journalctl -u caddy -f`
4. Verify domain in Caddy config

### Can't Connect to Internal Services

1. Check Tailscale status: `tailscale status`
2. Test connectivity: `tailscale ping david`
3. Verify service is running on internal server
4. Check Caddy reverse proxy config

### Out of Disk Space

```bash
# Clean old generations
sudo nix-collect-garbage -d

# Optimize store
sudo nix-store --optimize

# Check usage
du -sh /nix/store
```

## Cost Optimization

### Recommended VPS Specs

**Minimum**:
- 1 CPU core
- 1GB RAM
- 20GB disk
- ~$5-10/month

**Recommended**:
- 1-2 CPU cores
- 2GB RAM
- 25GB disk
- ~$10-15/month

### Providers by Price

- **Hetzner Cloud**: €3.79/mo (CX11: 2GB RAM, 20GB disk)
- **Vultr**: $5/mo (1GB RAM, 25GB disk)
- **DigitalOcean**: $6/mo (1GB RAM, 25GB disk)
- **Linode**: $5/mo (1GB RAM, 25GB disk)
- **Oracle Cloud**: Free tier available (1GB RAM)

## Quick Reference

### Common Commands

```bash
# Rebuild system
sudo nixos-rebuild switch --flake /etc/nixos#pits

# Update from git
cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake .#pits

# Check services
systemctl status caddy tailscaled

# View logs
journalctl -f
journalctl -u caddy -f

# Test internal connectivity
tailscale ping david

# Clean up disk space
sudo nix-collect-garbage -d
```

### File Locations

- Configuration: `/etc/nixos/hosts/pits/configuration.nix`
- Hardware config: `/etc/nixos/hosts/pits/hardware-configuration.nix`
- Profile: `/etc/nixos/profiles/edge.nix`
- Caddy config: Managed by NixOS configuration

### Architecture

Default in flake.nix: `aarch64-linux`

For x86_64 VPS, edit `flake.nix` line 166:
```nix
system = "x86_64-linux";  # Change from aarch64-linux
```

## Example Use Cases

### 1. Public Entry Point to Private Services

```nix
# pits acts as public gateway
# Internal services stay on private Tailscale network

services.caddy.virtualHosts."app.example.com" = {
  extraConfig = ''
    reverse_proxy http://david.tailscale:3000
  '';
};
```

### 2. Cloudflare Tunnel Alternative

Instead of Cloudflare tunnels, use pits + Tailscale for same functionality with more control.

### 3. Geographic Edge Node

Deploy multiple pits instances in different regions:
- `pits-us` in US
- `pits-eu` in Europe
- `pits-asia` in Asia

Route users to nearest edge for better performance.

## Success Criteria

✅ VPS accessible via SSH  
✅ Hostname is "pits"  
✅ Caddy running and accessible on ports 80/443  
✅ Tailscale connected to your network  
✅ Can access internal services via reverse proxy  
✅ HTTPS certificates working  
✅ Firewall configured properly  
✅ System updates working  

---

**Status**: Ready for cloud deployment  
**Last Updated**: October 13, 2025  
**Architecture**: x86_64-linux or aarch64-linux (configure in flake.nix)  
**Profile**: edge  
**Estimated Cost**: $5-15/month

