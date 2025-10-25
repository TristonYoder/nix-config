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

- **Encryption**: Uses PUBLIC keys (from `secrets.nix`) - no private key needed
- **Decryption**: Servers automatically use their SSH host private key (`/etc/ssh/ssh_host_ed25519_key`)
- **Admin keys**: Only needed on your local machine for managing/editing secrets

## Adding a Secret

### 1. Encrypt the secret value

**Recommended:** Use the helper script for easiest secret creation:

```bash
cd secrets

# Encrypt with all hosts (david, pits, admin)
./encrypt-secret.sh -n my-secret.age -h all -s "secret-value"
```

**Manual Method:** If you need full control, encrypt manually:

```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Step 1: Create a recipients file with SSH public keys
ssh tristonyoder@david "cat /etc/ssh/ssh_host_ed25519_key.pub" > /tmp/recipients.txt
ssh tristonyoder@pits "cat /etc/ssh/ssh_host_ed25519_key.pub" >> /tmp/recipients.txt
cat ~/.ssh/agenix.pub >> /tmp/recipients.txt

# Step 2: Encrypt with SSH public keys using -R flag
echo "MY_SECRET=secret-value" > /tmp/secret-plain.txt
nix-shell -p age --run \
  "age --encrypt -R /tmp/recipients.txt -o my-secret.age /tmp/secret-plain.txt"

# Step 3: Clean up
rm /tmp/secret-plain.txt /tmp/recipients.txt
```

**Critical:** Must use `-R` (capital R) with SSH public keys, NOT `-r` with age keys!

**Why:** 
- `-r age1...` creates X25519 recipients (won't work with agenix)
- `-R ssh-pub-keys-file` creates ssh-ed25519 recipients (works with agenix)

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

### 1. Get the host's public key

```bash
# On the new host
ssh newhost "cat /etc/ssh/ssh_host_ed25519_key.pub" | nix-shell -p ssh-to-age --run "ssh-to-age"
```

### 2. Add to `secrets.nix`

```nix
let
  newhost = "age1xxxxxxxxx...";  # Public key from step 1
  
  newhostKeys = [ newhost ] ++ adminKeys;
in
{
  "my-secret.age".publicKeys = newhostKeys;  # Now newhost can decrypt this
}
```

### 3. Rekey secrets (if needed)

If the secret already exists and you're adding a new host, you'll need to re-encrypt it with the new recipient.

**Option A: Re-encrypt manually (recommended for reliability)**
```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Decrypt with your admin SSH key
nix-shell -p age --run "age --decrypt -i ~/.ssh/agenix my-secret.age" > /tmp/secret-plain.txt

# Create SSH recipients file with all hosts including the new one
ssh tristonyoder@david "cat /etc/ssh/ssh_host_ed25519_key.pub" > /tmp/recipients.txt
ssh tristonyoder@pits "cat /etc/ssh/ssh_host_ed25519_key.pub" >> /tmp/recipients.txt
ssh tristonyoder@newhost "cat /etc/ssh/ssh_host_ed25519_key.pub" >> /tmp/recipients.txt
cat ~/.ssh/agenix.pub >> /tmp/recipients.txt

# Re-encrypt with SSH public keys (-R flag)
nix-shell -p age --run \
  "age --encrypt -R /tmp/recipients.txt -o my-secret.age /tmp/secret-plain.txt"

# Clean up
rm /tmp/secret-plain.txt /tmp/recipients.txt
```

**Option B: Use agenix rekey (if you have access to decrypt)**
```bash
cd secrets
nix develop --command agenix -r -i ~/.ssh/agenix
```

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

```nix
# See secrets.nix for current keys
david = "age19my5vpmrvl5u9ug4frpdmuuemjhdgemgqjm6xunknmfjf6efvdxs232kym";
pits  = "age1jja99mf5qfczutr574nve8vhpt7azm8aq4ukqqrstdn0agud23nscazh6r";
admin = "age1m32sa7vq84004w6spg5tp7vzmszecxpp0da6z6dj8fxs70y34flshd46jq";
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

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# 1. Decrypt the secret (if you can)
nix-shell -p age --run "age --decrypt -i ~/.ssh/agenix yourfile.age" > /tmp/plain.txt

# 2. Re-encrypt with SSH public keys using the script
./encrypt-secret.sh -n yourfile.age -f /tmp/plain.txt

# 3. Verify it's correct
./encrypt-secret.sh -v yourfile.age

# 4. Clean up
rm /tmp/plain.txt

# 5. Commit and deploy
git add yourfile.age
git commit -m "fix: Re-encrypt with SSH public keys"
```

**2. Secret Encrypted for Wrong Hosts**

**Problem:** The server's SSH host key isn't in the recipient list.

**Diagnosis:**
```bash
# Get server's age key
ssh hostname "cat /etc/ssh/ssh_host_ed25519_key.pub" | nix-shell -p ssh-to-age --run "ssh-to-age"

# Compare with secrets.nix
grep "hostname =" secrets/secrets.nix
```

**Fix:** If keys don't match, update `secrets.nix` and re-encrypt:
```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

./encrypt-secret.sh -n yourfile.age -h all -f /tmp/plain.txt
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

### encrypt-secret.sh

Encrypts secrets using the correct method for agenix compatibility (SSH public keys with `-R` flag).

**Features:**
- Automatically fetches SSH public keys from servers
- Uses SSH public key encryption (`-R` flag) for agenix compatibility
- Validates encryption format (checks for ssh-ed25519 recipients)
- Validates environment variable format
- Interactive or command-line input
- Shows preview before encryption
- Provides next steps after encryption
- **NEW:** Verify mode to check existing secrets

**Examples:**
```bash
cd secrets

# On macOS/Darwin: Add nix to PATH first
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Interactive mode (recommended)
./encrypt-secret.sh -n api-token.age -e

# From command line with all hosts (default)
./encrypt-secret.sh -n db-password.age -h all -s "mypassword123"

# From command line (all hosts is default)
./encrypt-secret.sh -n db-password.age -s "mypassword123"

# From file
./encrypt-secret.sh -n cert.age -f /path/to/certificate.pem

# Only specific hosts
./encrypt-secret.sh -n david-only.age -h david -s "secret"

# Multiple hosts
./encrypt-secret.sh -n multi-host.age -h david,pits -s "secret"

# Environment variable format
./encrypt-secret.sh -n token.age -e -s "API_KEY=abc123"

# Verify an existing secret has correct format
./encrypt-secret.sh -v cloudflare-api-token.age
```

**What it checks:**
- ✓ Fetches actual SSH host keys from servers
- ✓ Uses `-R` flag for SSH public key encryption
- ✓ Suppresses stderr to prevent file contamination
- ✓ Verifies result has `ssh-ed25519` recipients (not `X25519`)
- ✓ Warns if encryption format is wrong

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

