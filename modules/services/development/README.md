# Development Services

This directory contains NixOS modules for development-related services.

## Available Services

### Kasm Workspaces (`kasm.nix`)

Kasm Workspaces provides containerized desktop and application streaming.

#### Features
- Native NixOS service (uses `services.kasmweb`)
- Automatic Docker integration
- PostgreSQL and Redis backends (managed automatically)
- HTTPS reverse proxy via Caddy
- **Secure agenix-managed secrets** for all passwords
- Configurable SSL certificates
- Firewall rules automatically configured

#### Configuration Options

```nix
modules.services.development.kasm = {
  enable = true;
  domain = "kasm.theyoder.family";           # Default domain
  listenPort = 5443;                          # HTTPS port
  listenAddress = "0.0.0.0";                  # Bind address
  datastorePath = "/data/docker-appdata/kasm"; # Data directory
  networkSubnet = "172.20.0.0/16";            # Docker network subnet
  
  # Security: Use agenix secrets (default and recommended)
  useAgenixSecrets = true;  # Default: true
  
  # Optional: Use custom SSL certificates
  sslCertificate = null;      # Path to cert or null for self-signed
  sslCertificateKey = null;   # Path to key or null for self-signed
  
  # Alternative: Plaintext passwords (NOT RECOMMENDED - for testing only)
  # useAgenixSecrets = false;
  # adminPassword = "secure-password-here";
  # userPassword = "secure-password-here";
  # redisPassword = "secure-password-here";
  # postgres.password = "secure-password-here";
};
```

#### Security with Agenix (Recommended)

The module uses **agenix** to securely manage all sensitive passwords. This is enabled by default with `useAgenixSecrets = true`.

**Required secrets:**
- `kasm-admin-password` - Admin user password
- `kasm-user-password` - Regular user password
- `kasm-redis-password` - Redis backend password
- `kasm-postgres-password` - PostgreSQL backend password

##### Creating Secrets

Before deploying Kasm, you must create the four required secrets:

```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Generate secure random passwords
ADMIN_PASS=$(openssl rand -base64 32)
USER_PASS=$(openssl rand -base64 32)
REDIS_PASS=$(openssl rand -base64 32)
POSTGRES_PASS=$(openssl rand -base64 32)

# Encrypt each secret
./encrypt-secret.sh -n kasm-admin-password.age -s "$ADMIN_PASS"
./encrypt-secret.sh -n kasm-user-password.age -s "$USER_PASS"
./encrypt-secret.sh -n kasm-redis-password.age -s "$REDIS_PASS"
./encrypt-secret.sh -n kasm-postgres-password.age -s "$POSTGRES_PASS"

# Save passwords securely (use a password manager!)
echo "Kasm Admin Password: $ADMIN_PASS"
echo "Kasm User Password: $USER_PASS"
echo "Kasm Redis Password: $REDIS_PASS"
echo "Kasm PostgreSQL Password: $POSTGRES_PASS"
```

**Important**: Save these passwords in a password manager! You'll need the admin password to log in.

##### Verifying Secrets

Check that secrets are encrypted correctly:

```bash
cd secrets
./encrypt-secret.sh -v kasm-admin-password.age
./encrypt-secret.sh -v kasm-user-password.age
./encrypt-secret.sh -v kasm-redis-password.age
./encrypt-secret.sh -v kasm-postgres-password.age
```

Each should show `✓ ssh-ed25519 recipients found - compatible with agenix`.

##### Viewing Secrets

To view a secret (requires your admin SSH key):

```bash
cd secrets
./decrypt-secret.sh kasm-admin-password.age
```

#### Default Credentials

After deployment, log in with:
- **Admin**: `admin@kasm.local` / (password from kasm-admin-password secret)
- **User**: `user@kasm.local` / (password from kasm-user-password secret)

**Security Note**: These are the initial default accounts created by Kasm. After first login:
1. Change passwords in Kasm admin panel
2. Create proper user accounts
3. Consider disabling the default user account

#### Usage

##### 1. Create Secrets (First Time Only)

See "Creating Secrets" section above.

##### 2. Enable in Configuration

The module is enabled by default in the server profile. To customize:

```nix
# In hosts/david/configuration.nix
modules.services.development.kasm = {
  enable = true;
  domain = "workspaces.example.com";
  # All passwords are managed via agenix by default
};
```

##### 3. Deploy

```bash
# Commit the encrypted secrets
git add secrets/kasm-*.age
git commit -m "Add Kasm secrets"

# Deploy to server
sudo nixos-rebuild switch --flake .#your-host
```

##### 4. Access Kasm

- Via Caddy (HTTPS): `https://your-domain`
- Direct access: `https://your-domain:5443`

#### How It Works

1. **Service Management**: Uses native `services.kasmweb` from NixOS
2. **Secret Management**: Agenix decrypts secrets to `/run/agenix/` at boot
3. **Password Loading**: Passwords are read from decrypted secret files
4. **Docker Backend**: Automatically enables Docker for running workspace containers
5. **Databases**: PostgreSQL and Redis are managed by the Kasm service
6. **Networking**: Creates isolated Docker network for workspace containers
7. **Reverse Proxy**: Caddy provides HTTPS termination and routes to Kasm backend
8. **Data Persistence**: All data stored in configurable `datastorePath`

#### Integration with Caddy

The module automatically configures Caddy reverse proxy when `modules.services.infrastructure.caddy.enable = true`. The proxy:
- Handles HTTPS with Cloudflare DNS challenge
- Forwards requests to Kasm's internal HTTPS endpoint
- Skips certificate verification for Kasm's self-signed cert (when using internal SSL)

#### Disabling Agenix (Not Recommended)

For testing or development environments, you can disable agenix and use plaintext passwords:

```nix
modules.services.development.kasm = {
  enable = true;
  useAgenixSecrets = false;
  adminPassword = "test-admin-password";
  userPassword = "test-user-password";
  redisPassword = "test-redis-password";
  postgres.password = "test-postgres-password";
};
```

⚠️ **WARNING**: This stores passwords in the Nix store, which is world-readable! Only use for testing.

#### Troubleshooting

##### "Kasm useAgenixSecrets is enabled but agenix secrets are not configured"

**Solution**: Create the four required secrets as shown in "Creating Secrets" section.

##### "no identity matched any of the recipients"

**Solution**: The secret files weren't encrypted for your server. See `/secrets/README.md` for troubleshooting.

##### Can't log in with admin credentials

1. Verify the secret contains the password you expect:
   ```bash
   cd secrets
   ./decrypt-secret.sh kasm-admin-password.age
   ```

2. Check Kasm logs:
   ```bash
   journalctl -u kasmweb -f
   ```

3. Verify secrets are decrypted on the server:
   ```bash
   sudo ls -la /run/agenix/kasm-*
   ```

##### Need to reset passwords

1. Update the encrypted secrets:
   ```bash
   cd secrets
   NEW_PASS=$(openssl rand -base64 32)
   ./encrypt-secret.sh -n kasm-admin-password.age -s "$NEW_PASS"
   echo "New admin password: $NEW_PASS"
   ```

2. Deploy changes:
   ```bash
   git add secrets/kasm-admin-password.age
   git commit -m "Update Kasm admin password"
   sudo nixos-rebuild switch --flake .#your-host
   ```

3. Restart Kasm service:
   ```bash
   sudo systemctl restart kasmweb
   ```

#### Advanced Configuration

##### Custom SSL Certificates

To use your own SSL certificates instead of self-signed:

```nix
modules.services.development.kasm = {
  enable = true;
  sslCertificate = /path/to/cert.pem;
  sslCertificateKey = /path/to/key.pem;
};
```

##### Custom Data Directory

To use a different data storage location:

```nix
modules.services.development.kasm = {
  enable = true;
  datastorePath = "/mnt/storage/kasm";
};
```

##### Custom Docker Network

To use a different Docker network subnet:

```nix
modules.services.development.kasm = {
  enable = true;
  networkSubnet = "10.20.0.0/16";
};
```

### VS Code Server (`vscode-server.nix`)

Enables VS Code Remote SSH server support.

### GitHub Actions Runner (`github-actions.nix`)

Self-hosted GitHub Actions runner for CI/CD.

## Related Documentation

- **Secrets Management**: See `/secrets/README.md` for comprehensive agenix documentation
- **Kasm Documentation**: https://www.kasmweb.com/docs/
- **NixOS Kasm Options**: `services.kasmweb.*` in nixpkgs
