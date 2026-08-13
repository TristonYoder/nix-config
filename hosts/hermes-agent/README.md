# hermes-agent - Hermes AI Agent Host

Edge server configuration for the Hermes AI agent runtime.

## Overview

**hermes-agent** is a lightweight edge server that will run the [Hermes Agent](https://github.com/NousResearch/hermes-agent) — an autonomous AI agent framework using Nous Research's Hermes models. Initially provisioned with just the edge profile basics; services will be added as the agent stack matures.

- **Edge host** with edge profile infrastructure (Caddy, Tailscale, Headscale)
- **No active services yet** — ready for agent runtime when ready
- **Tailscale-connected** for secure access to the main network

## Specifications

- **Hostname**: hermes-agent
- **Profile**: edge (`profiles/edge.nix`)
- **Architecture**: x86_64-linux
- **User**: tristonyoder
- **Services**: None (edge infrastructure only)
- **Purpose**: Hermes AI agent host

## Quick Setup

### Remote Deployment

```bash
# Get hardware config from target
ssh root@<VPS_IP> nixos-generate-config --show-hardware-config > hosts/hermes-agent/hardware-configuration.nix

# Commit it
git add hosts/hermes-agent/hardware-configuration.nix
git commit -m "Update hermes-agent hardware config"

# Deploy (builds locally, faster)
nixos-rebuild switch --flake .#hermes-agent \
  --target-host root@<VPS_IP> \
  --build-host localhost
```

## Post-Setup Verification

```bash
# Check services
systemctl status tailscaled

# Join Tailnet
sudo tailscale up

# Verify connectivity
tailscale ping david
```

## Configuration

### Enabled (from edge profile)

- ✅ Caddy (reverse proxy)
- ✅ Tailscale (VPN)
- ✅ Headscale (Tailnet coordination)
- ✅ Technitium DNS
- ✅ OpenSSH (hardened)
- ✅ vscode-server (remote development)
- ✅ GitHub Actions runner

### Firewall

Open ports: 22 (SSH)

### Optimizations

The edge profile includes:
- Reduced journal size (50MB system, 25MB runtime)
- Daily garbage collection
- No desktop environment

## Roadmap

- [ ] Provision host and join Tailnet
- [ ] Generate real hardware config
- [ ] Enable Hermes Agent service module
- [ ] Configure agent model access and endpoints
- [ ] Add monitoring and health checks