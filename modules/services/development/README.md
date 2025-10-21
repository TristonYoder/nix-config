# Development Services

This directory contains NixOS modules for development-related services.

## Kasm Workspaces

Kasm Workspaces provides containerized desktop and application streaming for development and testing.

### Quick Start

Enable in your configuration:
```nix
modules.services.development.kasm.enable = true;
```

Access at `https://kasm.theyoder.family` (or your configured domain).

**Default credentials:**
- Username: `admin@kasm.local`
- Password: `changeme123`

⚠️ **Change the admin password immediately after first login!**

### Configuration

```nix
modules.services.development.kasm = {
  enable = true;
  domain = "kasm.example.com";           # Default: kasm.theyoder.family
  listenPort = 5443;                     # HTTPS port
  datastorePath = "/data/kasm";          # Data storage location
  
  # Security - Set custom passwords
  adminPassword = "your-secure-password";  # Change after first login!
  userPassword = "user-password";
  
  # Local-only database passwords (auto-configured)
  redisPassword = "kasm-redis-local";
  postgres.password = "kasm-postgres-local";
};
```

### Features

- **Native NixOS integration** - Uses `services.kasmweb`
- **Automatic setup** - PostgreSQL, Redis, and Docker configured automatically
- **HTTPS reverse proxy** - Caddy integration for SSL termination
- **Declarative** - Fully reproducible configuration
- **Firewall rules** - Port 5443 automatically opened

### Post-Installation

After deployment:
1. Access `https://your-domain`
2. Login with `admin@kasm.local` / your admin password
3. **Change admin password** in Kasm UI
4. Create proper user accounts
5. Configure workspace images in admin panel

### Troubleshooting

**Can't access Kasm:**
- Check service status: `sudo systemctl status kasmweb-api`
- Check containers: `sudo docker ps | grep kasm`
- Check logs: `sudo journalctl -u init-kasmweb -n 50`

**Network conflicts:**
- Default subnet: `172.22.0.0/16`
- If conflicts occur, override: `networkSubnet = "172.xx.0.0/16";`

**Password issues:**
- Passwords are configured at build time
- Change via NixOS config or in Kasm UI after login
- PostgreSQL/Redis passwords are local-only (low security risk)

### Integration

**With Caddy:**
Automatically configures reverse proxy when `modules.services.infrastructure.caddy.enable = true`

**With Docker:**
Automatically enables Docker for workspace containers

**With PostgreSQL/Redis:**
Managed by Kasm service, configured automatically

## Other Services

- **vscode-server** - VS Code Remote SSH support
- **github-actions** - Self-hosted GitHub Actions runner
