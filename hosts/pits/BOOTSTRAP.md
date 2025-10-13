# Quick Bootstrap Commands for pits

Single-command deployments for fresh NixOS VPS installations.

## Prerequisites

- Fresh NixOS VPS with console access
- Public IP address
- Root access

## Step 1: Enable SSH (via Console)

Access your VPS console (VNC/serial) and run:

```bash
# Enable and start SSH, set root password
sudo systemctl enable --now sshd && sudo passwd root
```

## Step 2: Bootstrap from Your Local Machine

### Option A: Single Command (Fastest)

```bash
# Replace <VPS_IP> with your actual VPS public IP
ssh root@<VPS_IP> 'nix-shell -p git --run "git clone https://github.com/TristonYoder/david-nixos.git /tmp/nixos-config && cd /tmp/nixos-config && sudo nixos-generate-config --show-hardware-config > hosts/pits/hardware-configuration.nix && sudo rm -rf /etc/nixos && sudo mv /tmp/nixos-config /etc/nixos && cd /etc/nixos && sudo nixos-rebuild switch --flake .#pits"'
```

### Option B: Remote Deployment (Build on Local Machine)

```bash
# Get hardware config from VPS
ssh root@<VPS_IP> nixos-generate-config --show-hardware-config > ~/Projects/david-nixos/hosts/pits/hardware-configuration.nix

# Commit it
cd ~/Projects/david-nixos
git add hosts/pits/hardware-configuration.nix
git commit -m "feat: Add pits hardware config"
git push

# Deploy remotely (builds on your Mac, faster)
nixos-rebuild switch --flake ~/Projects/david-nixos#pits \
  --target-host root@<VPS_IP> \
  --build-host localhost
```

### Option C: Step-by-Step (For Troubleshooting)

```bash
# SSH into VPS
ssh root@<VPS_IP>

# Use git temporarily (base NixOS doesn't include git)
nix-shell -p git

# Clone the repo
git clone https://github.com/TristonYoder/david-nixos.git /etc/nixos

# Exit nix-shell
exit

# Generate hardware config
cd /etc/nixos
sudo nixos-generate-config --show-hardware-config > hosts/pits/hardware-configuration.nix

# Deploy (git will be permanent after this)
sudo nixos-rebuild switch --flake .#pits

# Reboot
sudo reboot
```

## Step 3: Post-Bootstrap

After the first successful rebuild:

```bash
# SSH back in (SSH config is now permanent)
ssh tristonyoder@<VPS_IP>  # or root@<VPS_IP>

# Set user password if needed
sudo passwd tristonyoder

# Configure Tailscale
sudo tailscale up

# Configure Caddy reverse proxies
# Edit /etc/nixos/hosts/pits/configuration.nix
# Then rebuild:
sudo nixos-rebuild switch --flake /etc/nixos#pits
```

## Troubleshooting Bootstrap

### SSH Not Working After Step 1

```bash
# Via console, check SSH status
systemctl status sshd

# Check firewall
iptables -L | grep ssh

# Restart SSH
systemctl restart sshd
```

### Git Clone Fails

```bash
# Verify internet connectivity
ping 8.8.8.8

# Check DNS
ping github.com

# Try with HTTPS
nix-shell -p git --run "git clone https://github.com/TristonYoder/david-nixos.git /etc/nixos"
```

### Build Fails

```bash
# Check syntax
cd /etc/nixos
nix flake check

# Build with verbose output
sudo nixos-rebuild switch --flake .#pits --show-trace

# Check disk space
df -h
```

### Base NixOS Missing Tools

Remember: Base NixOS is minimal. Common tools need `nix-shell`:

```bash
# Temporarily get any tool
nix-shell -p git curl wget vim htop

# Or multiple tools
nix-shell -p git vim htop

# After first rebuild, git is permanent (included in common.nix)
```

## What Gets Installed

After successful bootstrap, your VPS will have:

- ✅ **SSH** - Configured and running (port 22)
- ✅ **Git** - Permanent (from common.nix)
- ✅ **Caddy** - Reverse proxy (ports 80, 443)
- ✅ **Tailscale** - VPN client
- ✅ **User Account** - tristonyoder with sudo access
- ✅ **Firewall** - Configured for 22, 80, 443
- ✅ **Automatic Updates** - Optional (if enabled in config)

## Next Steps

After bootstrap:

1. **Set up Tailscale**: `sudo tailscale up`
2. **Configure DNS**: Point your domain to VPS IP
3. **Add Caddy routes**: Edit `hosts/pits/configuration.nix`
4. **Test services**: Verify Caddy is serving correctly
5. **Harden security**: Disable password auth, set up fail2ban

See `INSTALLATION.md` for complete setup guide.

---

**Estimated Bootstrap Time**: 5-15 minutes (depending on VPS speed and network)

