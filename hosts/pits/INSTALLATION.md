# Installing NixOS on pits (Pi in the Sky)

Complete guide for setting up the pits edge server from scratch.

## Prerequisites

- Raspberry Pi 4 or 5 (or other ARM/x86 edge device)
- SD card (32GB+ recommended)
- Network connection (Ethernet recommended for initial setup)
- Access to download NixOS ARM image

## Part 1: Initial NixOS Installation

### Step 1: Download NixOS Image

```bash
# On your local machine
# Download the NixOS ARM image for Raspberry Pi
# Visit: https://nixos.org/download.html#nixos-iso
# Or use direct link for latest:
wget https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-aarch64-linux.iso

# For Raspberry Pi, you might want the SD image instead:
wget https://hydra.nixos.org/build/latest/download/1/nixos-sd-image-*-aarch64-linux.img.zst
```

### Step 2: Flash to SD Card

```bash
# Extract the image if compressed
unzstd nixos-sd-image-*-aarch64-linux.img.zst

# Flash to SD card (replace /dev/sdX with your SD card device)
# WARNING: This will erase all data on the SD card!
sudo dd if=nixos-sd-image-*-aarch64-linux.img of=/dev/sdX bs=4M status=progress
sync
```

### Step 3: Boot the Raspberry Pi

1. Insert SD card into Raspberry Pi
2. Connect Ethernet cable
3. Power on the Pi
4. Wait for it to boot (1-2 minutes)

### Step 4: Find the Pi's IP Address

```bash
# From your local machine, scan the network
# Or check your router's DHCP leases

# Try to find it via hostname
ping nixos.local

# Or scan the network
nmap -sn 192.168.1.0/24 | grep -B 2 "Raspberry"
```

### Step 5: SSH into the Pi

```bash
# Default NixOS image has SSH enabled with password authentication
# Default user: nixos (no password) or root

ssh nixos@<PI_IP_ADDRESS>
# or
ssh root@<PI_IP_ADDRESS>
```

## Part 2: Initial System Configuration

### Step 1: Set Up Network (if needed)

```bash
# If using WiFi instead of Ethernet
sudo nmcli device wifi connect "SSID" password "PASSWORD"

# Set a static IP (optional but recommended for edge server)
# Edit /etc/nixos/configuration.nix and add:
# networking.interfaces.eth0.ipv4.addresses = [{
#   address = "192.168.1.100";
#   prefixLength = 24;
# }];
# networking.defaultGateway = "192.168.1.1";
# networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
```

### Step 2: Set Root Password

```bash
sudo passwd root
```

### Step 3: Generate Hardware Configuration

```bash
sudo nixos-generate-config --show-hardware-config
```

**Important**: Copy this output! You'll need to replace the placeholder in `hosts/pits/hardware-configuration.nix`

## Part 3: Deploy Your Configuration

### Option A: Clone and Build on the Pi (Recommended for First Install)

```bash
# Install git (temporarily)
nix-shell -p git

# Clone your repository
git clone https://github.com/TristonYoder/david-nixos.git /etc/nixos
cd /etc/nixos

# Replace the placeholder hardware configuration
# Paste the output from nixos-generate-config above
sudo nano hosts/pits/hardware-configuration.nix

# Verify the hostname is set correctly
cat hosts/pits/configuration.nix | grep hostName
# Should show: networking.hostName = "pits";

# Build and switch to the new configuration
sudo nixos-rebuild switch --flake .#pits

# Reboot to ensure everything works
sudo reboot
```

### Option B: Deploy Remotely from Your Mac

```bash
# On your local machine (tyoder-mbp)
cd ~/Projects/david-nixos

# First, you need to get the hardware config from the Pi
ssh root@<PI_IP> nixos-generate-config --show-hardware-config > hosts/pits/hardware-configuration.nix

# Review and edit if needed
nano hosts/pits/hardware-configuration.nix

# Commit the hardware config
git add hosts/pits/hardware-configuration.nix
git commit -m "feat: Add actual hardware config for pits"
git push

# Deploy remotely (requires SSH access and root password)
nixos-rebuild switch --flake .#pits \
  --target-host root@<PI_IP> \
  --build-host localhost

# Or let it build on the Pi:
nixos-rebuild switch --flake .#pits \
  --target-host root@<PI_IP>
```

## Part 4: Post-Installation Setup

### Step 1: Create User Account

```bash
# SSH back into pits after reboot
ssh root@pits  # Should work via hostname now

# The user should already be created by the config
# Set the password for tristonyoder
passwd tristonyoder

# Test SSH with the user account
# From another terminal:
ssh tristonyoder@pits
```

### Step 2: Verify Services are Running

```bash
# Check Caddy
systemctl status caddy

# Check Tailscale
systemctl status tailscaled

# Check Docker (if needed)
systemctl status docker
```

### Step 3: Configure Tailscale (if using)

```bash
# Authenticate with Tailscale
sudo tailscale up

# Check status
tailscale status
```

### Step 4: Configure Caddy for Your Services

```bash
# Edit the pits configuration to add your reverse proxy rules
sudo nano /etc/nixos/hosts/pits/configuration.nix

# Example: Add a reverse proxy to an internal service
# services.caddy.virtualHosts."service.yourdomain.com" = {
#   extraConfig = ''
#     reverse_proxy http://internal-server.tailscale:8080
#   '';
# };

# Rebuild after changes
sudo nixos-rebuild switch --flake /etc/nixos#pits
```

### Step 5: Set Up Automatic Updates (Optional)

```bash
# Edit pits configuration
sudo nano /etc/nixos/hosts/pits/configuration.nix

# Uncomment the auto-update section:
# system.autoUpgrade = {
#   enable = true;
#   allowReboot = false;
#   dates = "daily";
#   flake = "github:TristonYoder/david-nixos#pits";
# };

# Rebuild
sudo nixos-rebuild switch --flake /etc/nixos#pits
```

## Part 5: Verification

### Check System Status

```bash
# Verify hostname
hostname
# Should output: pits

# Check NixOS version
nixos-version

# Verify flake configuration
nix flake show /etc/nixos

# Check system services
systemctl --failed

# View system logs
journalctl -xe

# Check disk usage
df -h

# Check memory usage
free -h
```

### Test Network Connectivity

```bash
# Test internal network
ping 192.168.1.1

# Test internet
ping 8.8.8.8

# Test DNS
ping google.com

# Test Tailscale (if configured)
tailscale ping david  # Ping your main server
```

## Troubleshooting

### Pi Won't Boot

1. Re-flash the SD card
2. Try a different power supply (Pi needs 5V 3A+)
3. Check SD card isn't corrupted

### Can't SSH In

```bash
# Check if Pi is on network
ping <PI_IP>

# Verify SSH is running on Pi (from console)
systemctl status sshd

# Check firewall
sudo iptables -L
```

### Build Fails

```bash
# Check for syntax errors
nix flake check /etc/nixos

# Build with verbose output
sudo nixos-rebuild switch --flake .#pits --show-trace

# Check available disk space
df -h
```

### Out of Space

```bash
# Clean up old generations
sudo nix-collect-garbage -d

# Optimize nix store
sudo nix-store --optimize
```

## Architecture Notes

### If Using x86_64 Instead of ARM

Edit `flake.nix` on line 166:

```nix
# Change from:
system = "aarch64-linux";

# To:
system = "x86_64-linux";
```

Then rebuild.

## Quick Reference

### Common Commands

```bash
# Rebuild system
sudo nixos-rebuild switch --flake /etc/nixos#pits

# Update flake inputs
cd /etc/nixos
nix flake update
sudo nixos-rebuild switch --flake .#pits

# Pull latest config from git
cd /etc/nixos
git pull
sudo nixos-rebuild switch --flake .#pits

# Check system status
systemctl status

# View logs
journalctl -f

# Rollback to previous generation
sudo nixos-rebuild switch --rollback
```

### File Locations

- Configuration: `/etc/nixos/hosts/pits/configuration.nix`
- Hardware config: `/etc/nixos/hosts/pits/hardware-configuration.nix`
- Profile: `/etc/nixos/profiles/edge.nix`
- Common settings: `/etc/nixos/common.nix`

## Success Criteria

✅ Pi boots and gets IP address  
✅ Can SSH in as tristonyoder  
✅ Hostname is "pits"  
✅ Caddy is running  
✅ Tailscale is connected (if configured)  
✅ System is accessible from internet (if public IP configured)  
✅ Can rebuild configuration successfully  

---

**Status**: Ready for deployment  
**Last Updated**: October 13, 2025  
**Architecture**: aarch64-linux (Raspberry Pi)  
**Profile**: edge

