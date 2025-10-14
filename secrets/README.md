# Secrets Management

Encrypted secrets using [agenix](https://github.com/ryantm/agenix). All `.age` files are safe to commit.

## Quick Start

**Helper Scripts (Recommended):**
```bash
# Encrypt a new secret
./encrypt-secret.sh -n my-secret.age -e

# Decrypt/view a secret
./decrypt-secret.sh cloudflare-api-token.age

# See all options
./encrypt-secret.sh --help
./decrypt-secret.sh --help
```

## How It Works

- **Encryption**: Uses PUBLIC keys (from `secrets.nix`) - no private key needed
- **Decryption**: Servers automatically use their SSH host private key (`/etc/ssh/ssh_host_ed25519_key`)
- **Admin keys**: Only needed on your local machine for managing/editing secrets

## Adding a Secret

### 1. Encrypt the secret value

**Important:** Use `age --encrypt` with **SSH public keys** (`-R` flag) for agenix compatibility.

```bash
cd secrets

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

This error during `nixos-rebuild` means the server cannot decrypt the secret. Common causes:

**1. Secret encrypted with wrong recipients**
- Verify the host's age public key matches `secrets.nix`:
  ```bash
  ssh hostname "cat /etc/ssh/ssh_host_ed25519_key.pub" | nix-shell -p ssh-to-age --run "ssh-to-age"
  ```
- If the key changed, update `secrets.nix` and re-encrypt all secrets

**2. Secret encrypted incorrectly**
- Must use `-R` with SSH public keys, NOT `-r` with age keys
- Check the file header: should show `-> ssh-ed25519`, not `-> X25519`
- Example:
  ```bash
  # Create SSH recipients file
  ssh tristonyoder@david "cat /etc/ssh/ssh_host_ed25519_key.pub" > /tmp/recipients.txt
  cat ~/.ssh/agenix.pub >> /tmp/recipients.txt
  
  # Encrypt with SSH keys
  echo "SECRET=value" > /tmp/plain.txt
  nix-shell -p age --run "age --encrypt -R /tmp/recipients.txt -o secret.age /tmp/plain.txt"
  rm /tmp/plain.txt /tmp/recipients.txt
  
  # Verify: should see "-> ssh-ed25519" not "-> X25519"
  head secret.age
  ```

**3. Verify decryption manually**
Test on the actual server:
```bash
# On the server
sudo bash -c 'cat /etc/ssh/ssh_host_ed25519_key | nix-shell -p ssh-to-age --run "ssh-to-age -private-key" > /tmp/key.txt && nix-shell -p age --run "age --decrypt -i /tmp/key.txt /path/to/secret.age" && rm /tmp/key.txt'
```

If manual decryption works but `nixos-rebuild` fails, ensure `modules/secrets.nix` has:
```nix
age.identityPaths = [
  "/etc/ssh/ssh_host_ed25519_key"
  "/etc/ssh/ssh_host_rsa_key"
];
```

## Helper Scripts Reference

### encrypt-secret.sh

Encrypts secrets using the correct method for agenix compatibility.

**Features:**
- Automatically includes all required recipients (david, pits, admin)
- Validates environment variable format
- Interactive or command-line input
- Shows preview before encryption
- Provides next steps after encryption

**Examples:**
```bash
# Interactive mode (recommended)
./encrypt-secret.sh -n api-token.age -e

# From command line
./encrypt-secret.sh -n db-password.age -s "mypassword123"

# From file
./encrypt-secret.sh -n cert.age -f /path/to/certificate.pem

# Only specific hosts
./encrypt-secret.sh -n david-only.age -h david -s "secret"

# Environment variable format
./encrypt-secret.sh -n token.age -e -s "API_KEY=abc123"
```

### decrypt-secret.sh

Decrypts secrets for viewing/editing using your admin key.

**Features:**
- Automatic SSH-to-age key conversion
- Output to stdout or file
- Clear error messages

**Examples:**
```bash
# View secret
./decrypt-secret.sh cloudflare-api-token.age

# Save to file
./decrypt-secret.sh -o /tmp/secret.txt my-secret.age

# Use different admin key
./decrypt-secret.sh -i ~/.ssh/id_ed25519 my-secret.age
```

