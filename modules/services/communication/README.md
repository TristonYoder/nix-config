# Communication Services

This directory contains NixOS modules for communication and collaboration services.

## Stalwart Mail Server

Modern all-in-one mail server with SMTP, IMAP, and JMAP support.

### Quick Info

- **Server**: `pits` (edge server)
- **Domain**: `test.7andco.dev` (test domain)
- **Admin Panel**: https://testmailadmin.7andco.studio
- **Webmail**: https://testmail.7andco.studio

### Setup Secrets

```bash
cd secrets
./regenerate-stalwart-secrets.sh
# Enter passwords when prompted (or use defaults)

cd ..
git add secrets/stalwart-*.age
git commit -m "Update Stalwart secrets"
git push
```

### Deploy

```bash
# Enabled by default in profiles/edge.nix for PITS

# Deploy from local machine:
nixos-rebuild switch --flake .#pits --target-host pits

# Or on PITS directly:
ssh pits
cd ~/Projects/nix-config
git pull
sudo nixos-rebuild switch --flake .
sudo systemctl restart stalwart-mail
```

### Setup DNS

```bash
export CLOUDFLARE_API_TOKEN='your-token'
./scripts/setup-mail-dns.sh
```

Creates all DNS records for `test.7andco.dev`. For production, add DKIM and configure reverse DNS.

### Access

**Admin Panel:**
- URL: https://testmailadmin.7andco.studio
- User: `admin`
- Password: Your admin web password

**Mail Accounts:**
- `postmaster@test.7andco.dev`
- `admin@test.7andco.dev`

**Mail Client (IMAP/SMTP):**
- Server: `mail.test.7andco.dev`
- IMAP Port: 993, SMTP Port: 465 (both SSL/TLS)

### Logs

```bash
ssh pits sudo journalctl -u stalwart-mail -f
```

## Pixelfed

Pixelfed is a federated photo-sharing platform, part of the ActivityPub network (Fediverse). It provides an Instagram-like experience with decentralized federation.

### Architecture

- **Server**: Runs on `david` (main server)
- **Reverse Proxy**: Served via Caddy on `pits` (edge server)
- **Public URL**: `https://pixelfed.theyoder.family`
- **Federation Domain**: `@username@theyoder.family` (via .well-known delegation)
- **Database**: MySQL (auto-created)
- **Port**: 8085 (nginx)

### Configuration

The Pixelfed service is enabled in `profiles/server.nix`:

```nix
modules.services.communication.pixelfed.enable = lib.mkDefault true;
```

### Key Features

- **MySQL Backend**: Automatically created and configured
- **Redis Caching**: Unix socket for performance
- **ActivityPub Federation**: Connect with Mastodon, Pixelfed, and other Fediverse instances
- **Closed Registration**: Admin-only user creation by default
- **Email Verification**: Required (can be bypassed manually via CLI)
- **Data Location**: `/data/docker-appdata/pixelfed`

### Post-Deployment Setup

After deploying to david, create your first admin user:

```bash
# SSH into david
ssh david

# Create a user account
sudo -u pixelfed pixelfed-manage user:create

# Follow the prompts for username, email, password

# Manually verify email (since email isn't configured yet)
sudo -u pixelfed pixelfed-manage user:verify your-username

# Make yourself an admin
sudo -u pixelfed pixelfed-manage user:admin your-username
```

Now visit `https://pixelfed.theyoder.family` and log in!

### Secrets

The Pixelfed APP_KEY is managed via agenix:

```bash
# The secret was already created during setup
# To view it:
cd secrets
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
nix-shell -p age --run "age --decrypt -i ~/.ssh/agenix pixelfed-env.age"
```

### Available Commands

```bash
# List all available artisan commands
sudo -u pixelfed pixelfed-manage list

# User management
sudo -u pixelfed pixelfed-manage user:create    # Create user
sudo -u pixelfed pixelfed-manage user:verify    # Verify email
sudo -u pixelfed pixelfed-manage user:admin     # Grant admin
sudo -u pixelfed pixelfed-manage user:delete    # Delete user

# Instance management
sudo -u pixelfed pixelfed-manage instance:actor # Create instance actor
sudo -u pixelfed pixelfed-manage import:cities  # Import location data

# Cache management
sudo -u pixelfed pixelfed-manage cache:clear    # Clear cache
sudo -u pixelfed pixelfed-manage config:cache   # Cache config
```

### Services

Pixelfed runs several systemd services:

```bash
# Main queue worker (background jobs)
systemctl status pixelfed-horizon.service

# PHP-FPM (web requests)
systemctl status phpfpm-pixelfed.service

# Nginx (web server)
systemctl status nginx.service

# MySQL (database)
systemctl status mysql.service

# Redis (caching/queues)
systemctl status redis-pixelfed.service

# Cron jobs (scheduled tasks)
systemctl status pixelfed-cron.timer
```

### Logs

```bash
# View Horizon queue worker logs
journalctl -u pixelfed-horizon -f

# View PHP-FPM logs
journalctl -u phpfpm-pixelfed -f

# View nginx access/error logs
journalctl -u nginx -f
```

### Well-Known Delegation

Federation discovery is handled by the centralized `wellknown.nix` module, which serves endpoints on both david and PITS. Your federated identity is `@username@theyoder.family` even though the web interface is at `pixelfed.theyoder.family`.

### Troubleshooting

**Can't access Pixelfed:**
- Check nginx is running: `systemctl status nginx`
- Check PHP-FPM is running: `systemctl status phpfpm-pixelfed`
- Test locally: `curl -I http://localhost:8085`
- Check PITS can reach david: `curl -I http://david:8085` (from PITS)

**Federation not working:**
- Test federation: Visit https://fediverse.party/en/pixelfed/ to find other Pixelfed instances to federate with
- Check well-known endpoints: `curl https://theyoder.family/.well-known/webfinger?resource=acct:username@theyoder.family`
- Verify ActivityPub is enabled in settings

**Database issues:**
- Check MySQL: `systemctl status mysql`
- View tables: `sudo -u mysql mysql pixelfed -e 'SHOW TABLES;'`

## Well-Known Federation Discovery

The `wellknown.nix` module centralizes federation discovery for all federated services (Matrix, Pixelfed, etc.).

### How It Works

The module automatically configures `.well-known` endpoints on the root domain (`theyoder.family`) differently based on the server:

- **Host Server (david)**: Serves `http://theyoder.family` internally, proxies to local services
- **Edge Servers (PITS)**: Serves `https://theyoder.family` publicly, proxies to david via Tailscale

### Supported Services

- **Matrix**: `/.well-known/matrix/server` and `/.well-known/matrix/client` (served directly)
- **Pixelfed**: `/.well-known/webfinger`, `/.well-known/host-meta`, `/.well-known/nodeinfo` (proxied to nginx:8085)

### Configuration

Enabled in both server and edge profiles:

```nix
modules.services.communication.wellknown.enable = lib.mkDefault true;
```

### Testing

```bash
# Test Matrix discovery
curl https://theyoder.family/.well-known/matrix/server

# Test Pixelfed discovery
curl https://theyoder.family/.well-known/webfinger?resource=acct:username@theyoder.family
```

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

## Mautrix-iMessage Bridge (BlueBubbles)

The mautrix-imessage bridge enables two-way bridging between Matrix and iMessage using a BlueBubbles server, allowing you to manage your iMessage conversations from Matrix.

### Prerequisites

Before enabling this bridge, you need:

1. **BlueBubbles Server** running on a Mac or iOS device
   - Download from: https://bluebubbles.app/
   - Configure and start the server
   - Note the server URL and password
   - Ensure the server is accessible from your NixOS machine (Tailscale recommended)

2. **Matrix Synapse** enabled (automatically checked by the module)

### Setup

#### 1. Encrypt BlueBubbles Password

Use agenix to securely store your BlueBubbles password:

```bash
cd secrets
./encrypt-secret.sh -n bluebubbles-password.age -e
# Enter your BlueBubbles server password when prompted
```

Commit the encrypted secret:
```bash
git add bluebubbles-password.age
git commit -m "Add encrypted BlueBubbles password"
```

#### 2. Enable the Bridge

Add to your NixOS configuration:

```nix
modules.services.communication.mautrix-imessage = {
  enable = true;
  
  # BlueBubbles server connection
  blueBubblesUrl = "http://macservices:1234";  # Your BlueBubbles server URL
  
  # Password automatically loaded from /run/agenix/bluebubbles-password
  
  # Add users who can use the bridge
  provisioningWhitelist = [
    "@youruser:theyoder.family"
  ];
};
```

#### 3. Deploy

```bash
sudo nixos-rebuild switch
```

#### 4. Link Your iMessage Account

In your Matrix client (Element, etc.):
1. Start a DM with: `@imessagebot:theyoder.family`
2. Send: `login`
3. Your iMessage chats will sync to Matrix

### Configuration Options

```nix
modules.services.communication.mautrix-imessage = {
  enable = true;
  
  # BlueBubbles connection (required)
  blueBubblesUrl = "http://192.168.1.100:1234";
  
  # Users allowed to use the bridge
  provisioningWhitelist = [
    "@user1:theyoder.family"
    "@user2:theyoder.family"
  ];
  
  # Optional: Custom port (default: 29319)
  port = 29319;
  
  # Optional: Use custom password file
  # blueBubblesPasswordFile = "/path/to/password/file";
};
```

### Daily Use

**Available commands** (send to `@imessagebot:theyoder.family`):
- `help` - List available commands
- `sync` - Force sync conversations
- `logout` - Disconnect from BlueBubbles
- `login` - Reconnect to BlueBubbles

### Features

- Two-way message synchronization
- Media files (photos, videos, etc.)
- Read receipts and typing indicators
- Group chats
- Reactions and replies (with Private API enabled)

### BlueBubbles Server Setup

For best results:

1. **Network**: Use Tailscale to securely connect to your BlueBubbles server
2. **Private API**: Enable for full functionality (requires SIP disabled on macOS)
3. **Testing**: Verify connectivity with `curl http://your-bluebubbles-url:1234/api/v1/ping`

### Logs

```bash
# View bridge logs
journalctl -u mautrix-imessage -f

# Check service status
systemctl status mautrix-imessage
```

### Troubleshooting

**Bridge bot not responding:**
- Check service: `systemctl status mautrix-imessage`
- Check Matrix registration: `grep imessage /var/lib/matrix-synapse/homeserver.yaml`
- View logs: `journalctl -u mautrix-imessage -n 100`

**Can't connect to BlueBubbles:**
- Test connectivity: `curl http://your-bluebubbles-url:1234/api/v1/ping`
- Verify password: `ls -l /run/agenix/bluebubbles-password`
- Check firewall rules between servers
- Verify BlueBubbles server is running

**Messages not syncing:**
- Check BlueBubbles server status
- View bridge logs for errors
- Try logging out and back in
- Restart BlueBubbles server

**Missing features:**
- Enable Private API in BlueBubbles settings
- Update BlueBubbles to latest version

