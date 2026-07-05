# Secrets Management

Encrypted secrets using [agenix](https://github.com/ryantm/agenix). All `.age` files are safe to commit.

## Quick Start

**Helper Scripts (Recommended):**
```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Encrypt a new secret
./encrypt-secret.sh -n my-secret.age -e

# Decrypt/view a secret
./decrypt-secret.sh cloudflare-api-token.age

# See all options
./encrypt-secret.sh --help
./decrypt-secret.sh --help
```

## Service-Specific Secret Generation

For services requiring multiple secrets, use the dedicated generation scripts:

### Postal Mail Server
```bash
cd secrets
./generate-postal-secrets.sh
```
Generates 5 encrypted secrets:
- `postal-db-password.age` - MariaDB password
- `postal-rails-secret.age` - Rails secret key
- `postal-signing-key.age` - RSA signing key
- `postal-admin-email.age` - Admin email
- `postal-admin-password.age` - Admin password

### Stalwart Mail Server
```bash
cd secrets
./regenerate-stalwart-secrets.sh
```
Generates 3 encrypted secrets:
- `stalwart-postmaster-password.age` - Postmaster account
- `stalwart-admin-password.age` - Admin mail account
- `stalwart-admin-web-password.age` - Web admin interface

## How It Works

- **Encryption**: Uses SSH public keys from `secrets/keys/<host>.pub` — no private key needed, works offline, works from any device
- **Decryption**: Servers automatically use their SSH host private key (`/etc/ssh/ssh_host_ed25519_key`)
- **Admin key**: `~/.ssh/agenix.pub` on your local machine; `keys/admin.pub` is a committed fallback

### Keys folder

```
secrets/keys/
  david.pub
  pits.pub
  tristons-workstation.pub
  tristons-nixbook.pub
  tyoder-mbp.pub
  admin.pub
```

These are **SSH public keys** — not secrets, safe to commit. The `encrypt-secret.sh` script reads from this folder directly, so encryption works from any device without SSH access to the hosts.

## Adding a Secret

### 1. Encrypt the secret value

```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Encrypt for all hosts (david, pits, tristons-workstation, admin)
./encrypt-secret.sh -n my-secret.age -s "secret-value"

# Or for specific hosts
./encrypt-secret.sh -n david-only.age -h david -s "secret-value"
```

**Critical:** Must use `-R` (capital R) with SSH public keys, NOT `-r` with age keys.
- `-r age1...` creates X25519 recipients → **won't work with agenix**
- `-R ssh-keys-file` creates ssh-ed25519 recipients → **required by agenix**

The encrypted file must have `-> ssh-ed25519` recipients, not `-> X25519`.

### 2. Declare it in `modules/secrets.nix`

```nix
age.secrets.my-secret = {
  file = ../secrets/my-secret.age;
  owner = "service-user";  # Which user should own it
  group = "service-group";
  mode = "0400";
};
```

### 3. Use it in your service

```nix
# Option A: Service reads file directly
services.myservice = {
  passwordFile = config.age.secrets.my-secret.path;
};

# Option B: Load as systemd environment variable
systemd.services.myservice.serviceConfig = {
  EnvironmentFile = config.age.secrets.my-secret.path;
};
# Then reference in config: {$MY_SECRET}

# ❌ DON'T use builtins.readFile - secret doesn't exist at eval time!
```

## Adding a Host

### 1. Fetch the host's SSH public key

```bash
cd secrets
./fetch-host-keys.sh new-hostname
```

This writes `keys/new-hostname.pub` and prints the key. If the host isn't in the known-hosts list inside the script, it will prompt for the SSH target (`user@host`).

To refresh all known hosts at once:
```bash
./fetch-host-keys.sh
```

### 2. Re-encrypt secrets that should be accessible on the new host

```bash
cd secrets
./encrypt-secret.sh -n my-secret.age -h david,pits,new-hostname \
  -f <(./decrypt-secret.sh my-secret.age)
```

### 3. Add the host to `fetch-host-keys.sh`

Open `fetch-host-keys.sh` and add an entry to the `HOSTS` map:
```bash
[new-hostname]="user@new-hostname"
```

### When a host is reprovisioned

A fresh NixOS install generates a new SSH host key. Run `./fetch-host-keys.sh <hostname>` to update the key file, then re-encrypt any secrets that host needs.

## Admin Keys

Admin keys are for **local secret management only** (editing, encrypting). Servers use their own host keys for decryption.

```bash
# Create a dedicated key (recommended)
ssh-keygen -t ed25519 -f ~/.ssh/agenix -N ""
cat ~/.ssh/agenix.pub | ssh-to-age

# Or use your existing personal key
cat ~/.ssh/id_ed25519.pub | ssh-to-age

# Add to adminKeys list in secrets.nix
adminKeys = [
  "age1xxxxxxxxx..."  # Your key (stays on your local machine only)
];
```

**Note:** Admin keys are NOT copied to servers. Servers automatically decrypt using `/etc/ssh/ssh_host_ed25519_key`.

## Current Secrets

| Secret | Hosts | Used By |
|--------|-------|---------|
| `cloudflare-api-token.age` | david, pits | Caddy (DNS-01) |
| `matrix-registration-secret.age` | david | Matrix Synapse |
| `pixelfed-env.age` | david | Pixelfed |
| `bluebubbles-password.age` | david | mautrix-imessage bridge |
| `vaultwarden-admin-token.age` | david | Vaultwarden |
| `postgres-affine-password.age` | david | PostgreSQL |
| `tailscale-authkey-pits.age` | pits | Tailscale |
| `cloudflared-token.age` | pits | Cloudflared |

## Key Reference

SSH public keys are stored as files in `secrets/keys/`. To view current recipients:

```bash
ls secrets/keys/
cat secrets/keys/david.pub
```

To verify what recipients an encrypted file has:
```bash
./encrypt-secret.sh -v cloudflare-api-token.age
```

## Troubleshooting

### Error: "age: error: no identity matched any of the recipients"

This error during `nixos-rebuild` means the server cannot decrypt the secret. **This is the most common agenix error.**

#### Quick Diagnosis

```bash
# Step 1: Check the secret file format
head yourfile.age

# Should see "-> ssh-ed25519" (CORRECT):
#   age-encryption.org/v1
#   -> ssh-ed25519 QfFraw ...
#   -> ssh-ed25519 G/hviA ...

# If you see "-> X25519" (WRONG):
#   age-encryption.org/v1
#   -> X25519 ...
#   -> X25519 ...
# This is your problem! See "Wrong Encryption Method" below.

# Step 2: Use the verify script
cd secrets
./encrypt-secret.sh -v yourfile.age
```

#### Common Causes

**1. Wrong Encryption Method (Most Common)**

**Problem:** Secret was encrypted with age recipient keys (`-r age1...`) instead of SSH public keys (`-R ssh-pub-keys-file`).

**Symptoms:**
- File shows `-> X25519` recipients
- Works on your local machine but fails on servers
- Error: "no identity matched any of the recipients"

**Why this happens:**
- Age supports two types of encryption:
  - **X25519 (age keys)**: `age --encrypt -r age1abc...` - Creates X25519 recipients
  - **SSH keys**: `age --encrypt -R ssh-keys-file` - Creates ssh-ed25519 recipients
- Agenix requires SSH key encryption so servers can decrypt using `/etc/ssh/ssh_host_ed25519_key`
- If you use age keys from `secrets.nix` directly, you get X25519 (wrong!)

**Fix:**
```bash
cd secrets

# Re-encrypt in one step using process substitution
./encrypt-secret.sh -n yourfile.age -f <(./decrypt-secret.sh yourfile.age)

# Verify format
./encrypt-secret.sh -v yourfile.age

# Commit
git add yourfile.age && git commit -m "fix(secrets): re-encrypt with SSH public keys"
```

**2. Secret Encrypted for Wrong Hosts**

**Problem:** The server's SSH host key isn't in the recipient list.

**Diagnosis:**
```bash
# Refresh the host's key and re-encrypt
cd secrets
./fetch-host-keys.sh hostname
./encrypt-secret.sh -n yourfile.age -f <(./decrypt-secret.sh yourfile.age)
```

**3. Server SSH Key Changed**

**Problem:** Server was reinstalled or SSH keys regenerated.

**Symptoms:**
- Secrets that used to work now fail
- SSH host key doesn't match `secrets.nix`

**Fix:**
```bash
# 1. Get new host key
ssh hostname "cat /etc/ssh/ssh_host_ed25519_key.pub" | nix-shell -p ssh-to-age --run "ssh-to-age"

# 2. Update secrets.nix with new key
vim secrets/secrets.nix

# 3. Re-encrypt ALL secrets for that host
# (decrypt each one, then re-encrypt with updated keys)
```

**4. File Corrupted or Contaminated**

**Problem:** nix-shell warnings or other text mixed into the `.age` file.

**Symptoms:**
- Error: "failed to read header: parsing age header: unexpected intro"
- File doesn't start with `age-encryption.org/v1`

**Example of corrupted file:**
```
warning: ignoring the client-specified setting 'keep-derivations'
warning: ignoring the client-specified setting 'keep-outputs'
age-encryption.org/v1
...
```

**Fix:** The script now redirects stderr to prevent this (`2>/dev/null`). Re-encrypt the secret.

#### Manual Verification

Test decryption on the actual server:

```bash
# On the server (requires sudo)
ssh hostname

# Convert SSH private key to age format and test decrypt
sudo bash -c 'cat /etc/ssh/ssh_host_ed25519_key | \
  nix-shell -p ssh-to-age --run "ssh-to-age -private-key" > /tmp/age-key.txt && \
  nix-shell -p age --run "age --decrypt -i /tmp/age-key.txt /path/to/secret.age" && \
  rm /tmp/age-key.txt'
```

If manual decryption works but `nixos-rebuild` fails:

1. Check `modules/secrets.nix` has correct identityPaths:
```nix
age.identityPaths = [
  "/etc/ssh/ssh_host_ed25519_key"
  "/etc/ssh/ssh_host_rsa_key"
];
```

2. Verify secret file is in the nix store:
```bash
# The path will be in the error message
ls -l /nix/store/...-yourfile.age
head /nix/store/...-yourfile.age  # Check format
```

3. If nix store has old version, rebuild:
```bash
# Pull latest changes
git pull

# Rebuild (this updates nix store)
sudo nixos-rebuild switch
```

## Helper Scripts Reference

### fetch-host-keys.sh

Fetches SSH host public keys and writes them to `keys/<host>.pub`. Run when adding a new host or after a host is reprovisioned.

```bash
./fetch-host-keys.sh                        # refresh all known hosts
./fetch-host-keys.sh david pits             # refresh specific hosts
./fetch-host-keys.sh new-hostname           # fetch unknown host (prompts for SSH target)
```

### encrypt-secret.sh

Encrypts secrets using SSH public keys from `keys/` for agenix compatibility.

```bash
# Interactive mode (recommended)
./encrypt-secret.sh -n api-token.age -e

# From argument
./encrypt-secret.sh -n db-password.age -s "mypassword123"

# From file or process substitution
./encrypt-secret.sh -n cert.age -f /path/to/certificate.pem
./encrypt-secret.sh -n token.age -f <(./decrypt-secret.sh token.age)

# Specific hosts only
./encrypt-secret.sh -n david-only.age -h david -s "secret"
./encrypt-secret.sh -n multi.age -h david,pits -s "secret"

# Environment variable format
./encrypt-secret.sh -n token.age -e -s "API_KEY=abc123"

# Verify an existing secret has correct format
./encrypt-secret.sh -v cloudflare-api-token.age
```

### decrypt-secret.sh

Decrypts secrets for viewing/editing using your admin key.

**Features:**
- Automatic SSH-to-age key conversion
- Output to stdout or file
- Clear error messages

**Examples:**
```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# View secret
./decrypt-secret.sh cloudflare-api-token.age

# Save to file
./decrypt-secret.sh -o /tmp/secret.txt my-secret.age

# Use different admin key
./decrypt-secret.sh -i ~/.ssh/id_ed25519 my-secret.age
```

