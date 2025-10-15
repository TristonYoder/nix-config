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
register_new_matrix_user -c /var/lib/matrix-synapse/homeserver.yaml http://localhost:8448

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

- **8448**: Client-server and federation API (accessible over Tailscale, proxied via Caddy on pits)

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
- `clientPort`: Client-server and federation API port (default: `8448`)
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

## Mautrix-GroupMe Bridge

The mautrix-groupme bridge enables puppeting (two-way bridging) between Matrix and GroupMe, allowing you to manage your GroupMe conversations from Matrix.

### Architecture

- **Service**: Runs as a native systemd service on the same host as Matrix Synapse
- **Configuration**: Fully declarative - managed via NixOS options
- **Bridge Bot**: `@groupmebot:theyoder.family`
- **Repository**: [beeper/groupme](https://github.com/beeper/groupme)
- **Port**: 29318 (default)
- **Technology**: Modern Go-based mautrix bridge

### Quick Setup

The bridge is **fully automatic**! Just enable it and deploy:

```nix
# Already enabled in profiles/server.nix by default
modules.services.communication.mautrix-groupme.enable = true;
```

Deploy:
```bash
sudo nixos-rebuild switch
```

The module will:
- ✅ Build the bridge from source
- ✅ Generate configuration automatically
- ✅ Create registration file
- ✅ Register with Matrix Synapse
- ✅ Start the bridge service

### Configuration Options

Customize the bridge via NixOS options:

```nix
modules.services.communication.mautrix-groupme = {
  enable = true;
  
  # Add users who can use the bridge
  provisioningWhitelist = [
    "@youruser:theyoder.family"
  ];
  
  # Custom port (default: 29318)
  port = 29318;
  
  # Custom homeserver URL (auto-detected from Synapse config)
  homeserverUrl = "http://localhost:8448";
};
```

All configuration is declarative - just edit your NixOS config and rebuild!

### Using the Bridge

#### 1. Start a Conversation with the Bot

In your Matrix client (Element, etc.), start a DM with: `@groupmebot:theyoder.family`

#### 2. Link Your GroupMe Account

Send the command:
```
login
```

The bot will guide you through the authentication process for linking your GroupMe account.

#### 3. Access Your GroupMe Chats

After logging in, your GroupMe conversations will automatically appear as Matrix rooms. You can also use commands:

**List available commands:**
```
help
```

**Logout:**
```
logout
```

### Bridged Conversations

- GroupMe chats automatically bridge to Matrix rooms
- Messages sent in Matrix will appear in GroupMe and vice versa
- The bridge supports two-way puppeting
- Media files are bridged between platforms

### Logs

View bridge logs:

```bash
journalctl -u mautrix-groupme -f
```

### Troubleshooting

**Bridge bot not responding:**
- Check bridge is running: `systemctl status mautrix-groupme`
- Check Matrix Synapse loaded the registration: `grep groupme /var/lib/matrix-synapse/homeserver.yaml`
- Verify bridge logs: `journalctl -u mautrix-groupme -n 100`

**Can't login to GroupMe:**
- Check the bridge logs for authentication errors
- Ensure you're following the bot's login instructions exactly
- Verify the bridge can reach GroupMe's servers

**Messages not syncing:**
- Check GroupMe API status
- Verify bridge is running and not crashed
- Check bridge logs for errors
- Try logging out and back in

