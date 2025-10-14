# Matrix Synapse Deployment Guide

## Overview

Matrix Synapse has been configured to run on `david` with Caddy reverse proxy on `pits`. Users will have Matrix IDs in the format `@username:theyoder.family` while the actual server runs at `matrix.theyoder.family`.

## Architecture

```
Internet → pits (Caddy) → Tailscale → david (Matrix Synapse)
           ↓
    matrix.theyoder.family
    (+ .well-known delegation from theyoder.family)
```

- **Matrix Server**: david:8008 (client-server and federation)
- **Reverse Proxy**: pits (Caddy with Cloudflare DNS)
- **Public URL**: https://matrix.theyoder.family
- **User Domain**: @username:theyoder.family
- **Database**: PostgreSQL on david

## Deployment Steps

### 1. Deploy to David

```bash
# SSH into david
ssh david

# Switch to the new configuration
cd /etc/nixos  # or wherever your flake is located
git pull
git checkout feature/matrix-synapse
sudo nixos-rebuild switch --flake .#david

# Verify Matrix Synapse is running
systemctl status matrix-synapse
journalctl -u matrix-synapse -f
```

### 2. Deploy to Pits

```bash
# SSH into pits
ssh pits

# Switch to the new configuration
cd /etc/nixos  # or wherever your flake is located
git pull
git checkout feature/matrix-synapse
sudo nixos-rebuild switch --flake .#pits

# Verify Caddy is running
systemctl status caddy

# Test Tailscale connectivity to david
ping david
```

### 3. Verify Connectivity

From pits, test that Matrix is accessible:

```bash
curl http://david:8008/_matrix/client/versions
```

Should return JSON with Matrix versions.

### 4. Create Admin User

On david:

```bash
# Create your first user (admin)
sudo -u matrix-synapse register_new_matrix_user \
  -c /var/lib/matrix-synapse/homeserver.yaml \
  http://localhost:8008

# Follow the interactive prompts:
# - Username: your_username
# - Password: (enter secure password)
# - Make admin? yes
```

### 5. Test Public Access

From your local machine:

```bash
# Test client-server API
curl https://matrix.theyoder.family/_matrix/client/versions

# Test well-known delegation
curl https://theyoder.family/.well-known/matrix/server
curl https://theyoder.family/.well-known/matrix/client
```

### 6. Test Federation

1. Visit https://federationtester.matrix.org/
2. Enter `theyoder.family`
3. Verify all checks pass (particularly .well-known and federation)

### 7. Connect with Element

1. Go to https://app.element.io/
2. Click "Sign In"
3. Enter your Matrix ID: `@your_username:theyoder.family`
4. Element will auto-discover the homeserver via .well-known
5. Enter your password and sign in

## DNS Configuration

Ensure the following DNS records are configured:

```
matrix.theyoder.family  A      <pits-public-ip>
theyoder.family         A      <pits-public-ip>
```

Caddy will automatically obtain SSL certificates via Cloudflare DNS-01 challenge.

## Creating Additional Users

Only admins can create new users (closed registration):

```bash
# SSH into david
ssh david

# Create a new user
sudo -u matrix-synapse register_new_matrix_user \
  -c /var/lib/matrix-synapse/homeserver.yaml \
  http://localhost:8008
```

## Monitoring

### View Logs

```bash
# On david - Matrix Synapse logs
journalctl -u matrix-synapse -f

# On pits - Caddy logs
journalctl -u caddy -f
```

### Check Database

```bash
# On david
sudo -u postgres psql matrix-synapse
\dt  # List tables
\q   # Quit
```

## Troubleshooting

### Matrix Synapse won't start

```bash
# Check logs
journalctl -u matrix-synapse -xe

# Check if PostgreSQL is running
systemctl status postgresql

# Check if database exists
sudo -u postgres psql -l | grep matrix-synapse

# Verify secret is readable
sudo ls -l /run/agenix/matrix-registration-secret
```

### Can't connect from pits to david

```bash
# On pits, test Tailscale connectivity
ping david

# Check Tailscale status
tailscale status | grep david

# Test Matrix port
curl http://david:8008/_matrix/client/versions
```

### Federation not working

```bash
# Verify ports 80 and 443 are open on pits
sudo ss -tlnp | grep -E ':(80|443)'

# Check Caddy configuration
sudo systemctl status caddy
sudo journalctl -u caddy -n 50

# Test from external location
curl https://matrix.theyoder.family/_matrix/federation/v1/version
```

### Well-known not working

```bash
# Test from external location
curl -L https://theyoder.family/.well-known/matrix/server
curl -L https://theyoder.family/.well-known/matrix/client

# Should return JSON responses
```

## Security Considerations

1. **Closed Registration**: Only admins can create accounts
2. **Localhost Binding**: Matrix only listens on localhost + Tailscale
3. **Secure Proxy**: All traffic proxied through Caddy with SSL
4. **Secret Management**: Registration secret encrypted with agenix
5. **URL Preview Protection**: Blacklisted private IP ranges

## Backup and Maintenance

### Backup Database

PostgreSQL backups are already configured (see `modules/services/infrastructure/postgresql.nix`):

```bash
# On david
sudo -u postgres pg_dump matrix-synapse > /backup/matrix-synapse-$(date +%Y%m%d).sql
```

### Update Matrix Synapse

NixOS will update Matrix Synapse when you update your system:

```bash
# On david
sudo nixos-rebuild switch --flake .#david
```

## Additional Features

To add more features, modify `modules/services/communication/matrix-synapse.nix`:

- **Enable bridges**: Add bridges for WhatsApp, Telegram, Discord, etc.
- **Configure TURN server**: For better voice/video calls
- **Add workers**: Scale horizontally with worker processes
- **Enable push notifications**: Configure push gateway

## Support

- Matrix Synapse docs: https://matrix-org.github.io/synapse/
- Element client: https://element.io/
- Matrix spec: https://spec.matrix.org/

## Configuration Files

- Service module: `modules/services/communication/matrix-synapse.nix`
- Caddy proxy (pits): `hosts/pits/configuration.nix`
- Secrets: `modules/secrets.nix` and `secrets/matrix-registration-secret.age`
- Profile: `profiles/server.nix`

