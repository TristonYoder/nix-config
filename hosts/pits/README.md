# pits - Pi in the Sky

Edge server configuration for public-facing services.

## Overview

**pits** (Pi in the Sky) is a lightweight edge server designed to run on a Raspberry Pi or similar hardware with a public IP address. It serves as an entry point for services, running Caddy for reverse proxy and Tailscale for secure communication with the main infrastructure.

## Specifications

- **Hostname**: pits
- **Profile**: edge (`profiles/edge.nix`)
- **Architecture**: aarch64-linux (Raspberry Pi) - configurable in `flake.nix`
- **User**: tristonyoder
- **Services**: Caddy, Tailscale, vscode-server

## Purpose

This host acts as:
- **Public-facing edge node** with direct internet access
- **Reverse proxy** using Caddy to forward requests to internal services
- **VPN gateway** via Tailscale to securely connect to the main network
- **Lightweight entry point** optimized for minimal resource usage

## Installation

### 1. Prepare the Raspberry Pi

1. Download NixOS ARM image: https://nixos.org/download.html#nixos-iso
2. Flash to SD card using balenaEtcher or `dd`
3. Boot the Raspberry Pi
4. Set up networking (WiFi or Ethernet)

### 2. Initial NixOS Setup

```bash
# On the Raspberry Pi
sudo nixos-generate-config
```

### 3. Copy Hardware Configuration

Copy the generated `/etc/nixos/hardware-configuration.nix` to this directory:

```bash
# From your local machine (replace with actual Pi IP)
scp root@pits-ip:/etc/nixos/hardware-configuration.nix hosts/pits/
```

Or manually copy the content and replace the placeholder in `hosts/pits/hardware-configuration.nix`.

### 4. Configure Network

Edit `hosts/pits/configuration.nix` and set up your network:

**For DHCP (recommended for testing):**
```nix
networking.useDHCP = true;
```

**For static IP (recommended for production):**
```nix
networking.interfaces.eth0.ipv4.addresses = [{
  address = "YOUR_PUBLIC_IP";
  prefixLength = 24;
}];
networking.defaultGateway = "YOUR_GATEWAY";
networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
```

### 5. Set Up Secrets

Create Tailscale auth key secret:

```bash
# From development machine in the repo
nix develop
agenix -e secrets/tailscale-authkey-pits.age
# Add the Tailscale auth key
```

Update `secrets/secrets.nix` to include pits SSH key.

### 6. Deploy

**Initial deployment from the Pi itself:**
```bash
# Clone the repository on the Pi
git clone <your-repo-url> /etc/nixos/david-nixos
cd /etc/nixos/david-nixos

# Build and switch
sudo nixos-rebuild switch --flake .#pits
```

**Or deploy remotely:**
```bash
# From your local machine
nixos-rebuild switch --flake .#pits --target-host root@pits-ip --build-host localhost
```

## Configuration Details

### Enabled Services

- ✅ **Caddy** - Reverse proxy and web server
- ✅ **Tailscale** - VPN for secure networking
- ✅ **vscode-server** - Remote development access
- ✅ **OpenSSH** - Remote management (hardened)

### Optimizations

The edge profile includes optimizations for low-resource devices:

- **Reduced journal size**: 50MB system, 25MB runtime
- **Aggressive garbage collection**: Daily, keeps 7 days
- **Auto store optimization**: Enabled
- **zram swap**: Enabled (50% of RAM)
- **Headless**: No desktop environment

### Firewall

Open ports by default:
- **22** - SSH (consider changing to non-standard port)
- **80** - HTTP (Caddy)
- **443** - HTTPS (Caddy)

## Usage Examples

### Add a Reverse Proxy

Edit `hosts/pits/configuration.nix`:

```nix
services.caddy.virtualHosts."service.example.com" = {
  extraConfig = ''
    reverse_proxy http://internal-server.tailscale:8080
  '';
};
```

### Enable Cloudflare Tunnel

```nix
modules.services.infrastructure.cloudflared.enable = true;
```

### Monitor Resources

```bash
# SSH into pits
ssh tristonyoder@pits

# Check resource usage
htop
iotop

# Check service status
systemctl status caddy
systemctl status tailscaled

# View logs
journalctl -u caddy -f
journalctl -u tailscaled -f
```

## Security Considerations

As a public-facing server, security is critical:

1. **SSH Hardening**
   - Disable password authentication ✅ (already configured)
   - Disable root login ✅ (already configured)
   - Consider changing SSH port from 22

2. **Firewall**
   - Only open necessary ports
   - Use fail2ban or similar for brute force protection
   - Consider rate limiting in Caddy

3. **Updates**
   - Enable automatic security updates
   - Monitor for security advisories
   - Keep system updated regularly

4. **Monitoring**
   - Set up alerts for unusual activity
   - Monitor resource usage
   - Track Caddy access logs

5. **Secrets**
   - All secrets encrypted with agenix
   - Never commit plaintext credentials
   - Rotate secrets regularly

## Maintenance

### Update the System

```bash
# On pits
cd /etc/nixos/david-nixos
git pull
sudo nixos-rebuild switch --flake .#pits
```

### Check Logs

```bash
# System logs
journalctl -xe

# Specific service
journalctl -u caddy -f
journalctl -u tailscaled -f
```

### Rebuild After Changes

```bash
# From local machine
git commit -am "Update pits configuration"
git push
ssh tristonyoder@pits
cd /etc/nixos/david-nixos
git pull
sudo nixos-rebuild switch --flake .#pits
```

## Troubleshooting

### Can't Connect via SSH

- Check if the Pi is booting (LED activity)
- Verify network connection
- Check firewall rules
- Try connecting via serial console

### Caddy Not Starting

```bash
systemctl status caddy
journalctl -u caddy -xe
# Check configuration
caddy validate --config /etc/caddy/Caddyfile
```

### Out of Disk Space

```bash
# Clean up old generations
nix-collect-garbage -d

# Check disk usage
df -h
du -sh /nix/store
```

### Performance Issues

- Check available RAM: `free -h`
- Monitor CPU: `htop`
- Consider reducing journal size further
- Disable unnecessary services

## Architecture Options

If not using a Raspberry Pi, update `flake.nix`:

```nix
# For x86_64 (Intel/AMD)
pits = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";  # Change from aarch64-linux
  # ... rest of config
};
```

## Resources

- [NixOS on ARM](https://nixos.wiki/wiki/NixOS_on_ARM)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Tailscale Setup](https://tailscale.com/kb/)
- [Raspberry Pi 4](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)

---

**Status**: Ready for deployment  
**Last Updated**: October 13, 2025  
**Profile**: edge  
**Auto-detection**: Enabled (hostname: pits)

