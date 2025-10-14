# Communication Services

This directory contains NixOS modules for communication and collaboration services.

## Matrix Synapse

Matrix Synapse is a homeserver implementation for the Matrix protocol, enabling self-hosted instant messaging, VoIP, and collaboration.

### Architecture

- **Server**: Runs on `david` (main server)
- **Reverse Proxy**: Served via Caddy on `pits` (edge server)
- **Public URL**: `matrix.theyoder.family`
- **User Domain**: `@username:theyoder.family` (via .well-known delegation)

### Configuration

The Matrix Synapse service is enabled in `profiles/server.nix`:

```nix
modules.services.communication.matrix-synapse.enable = lib.mkDefault true;
```

### Key Features

- **PostgreSQL Backend**: Uses the existing PostgreSQL service on david
- **Closed Registration**: Admin-only user creation for security
- **Federation Enabled**: Can communicate with other Matrix servers
- **URL Previews**: Generates link previews with proper security restrictions
- **Secure Deployment**: Binds to localhost/Tailscale only, proxied through pits

### Post-Deployment Setup

After deploying to david, create your first user:

```bash
# SSH into david
ssh david

# Create admin user (interactive prompt)
register_new_matrix_user -c /var/lib/matrix-synapse/homeserver.yaml http://localhost:8009

# Follow prompts to create username, password, and grant admin privileges
```

### Testing

1. **Federation Test**:
   - Visit https://federationtester.matrix.org/
   - Enter `theyoder.family`
   - Verify all checks pass

2. **Client Connection**:
   - Use Element web client: https://app.element.io/
   - Click "Sign In"
   - Enter your Matrix ID: `@username:theyoder.family`
   - Server will auto-discover via .well-known delegation

### Well-Known Delegation

The `.well-known` files are served by Caddy on pits at the base domain `theyoder.family`:

- `/.well-known/matrix/server` - Points to `matrix.theyoder.family:443`
- `/.well-known/matrix/client` - Provides client discovery

This allows users to have IDs like `@username:theyoder.family` while the actual server runs at `matrix.theyoder.family`.

### Secrets

The Matrix registration shared secret is managed via agenix:

```nix
age.secrets.matrix-registration-secret = {
  file = ../secrets/matrix-registration-secret.age;
  owner = "matrix-synapse";
  group = "matrix-synapse";
  mode = "0400";
};
```

This secret is used by the `register_new_matrix_user` command to create new accounts.

### Ports

- **8009**: Client-server and federation API (accessible over Tailscale, proxied via Caddy on pits)

### Database

PostgreSQL database is automatically created:
- **Database**: `matrix-synapse`
- **User**: `matrix-synapse`
- **Location**: `/var/lib/matrix-synapse`

### Logs

View Matrix Synapse logs:

```bash
journalctl -u matrix-synapse -f
```

### Additional Configuration

The module provides several options (see `matrix-synapse.nix`):

- `serverName`: The domain for user IDs (default: `theyoder.family`)
- `publicBaseUrl`: Public URL for the homeserver (default: `https://matrix.theyoder.family`)
- `clientPort`: Client-server and federation API port (default: `8009`)
- `enableRegistration`: Allow open registration (default: `false`)
- `enableUrlPreviews`: Enable URL preview generation (default: `true`)

### Troubleshooting

**Can't connect to Matrix server:**
- Check Tailscale is running on both david and pits
- Verify `david` resolves from pits: `ping david` from pits
- Check Caddy is running on pits: `systemctl status caddy`
- Check Matrix Synapse is running on david: `systemctl status matrix-synapse`

**Federation not working:**
- Verify DNS records for `matrix.theyoder.family` point to pits
- Test federation: https://federationtester.matrix.org/
- Check firewall rules on pits allow ports 80 and 443

**Can't register users:**
- Verify registration secret exists: `ls -l /run/agenix/matrix-registration-secret`
- Check homeserver config: `cat /var/lib/matrix-synapse/homeserver.yaml`

