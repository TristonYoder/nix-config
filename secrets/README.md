# Secrets Management

Encrypted secrets using [agenix](https://github.com/ryantm/agenix). All `.age` files are safe to commit.

## How It Works

- **Encryption**: Uses PUBLIC keys (from `secrets.nix`) - no private key needed
- **Decryption**: Servers automatically use their SSH host private key (`/etc/ssh/ssh_host_ed25519_key`)
- **Admin keys**: Only needed on your local machine for managing/editing secrets

## Adding a Secret

### 1. Encrypt the secret value

```bash
cd secrets

# For environment file format (KEY=value - for systemd EnvironmentFile)
echo -n "MY_SECRET=secret-value" | nix-shell -p age --run \
  "age -r age19my5... -r age1jja99... -o my-secret.age"

# Or for raw value (if service reads file directly)
echo -n "secret-value" | nix-shell -p age --run \
  "age -r age19my5... -r age1jja99... -o my-secret.age"
```

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

If the secret already exists and you're adding a new host:

```bash
cd secrets
nix develop --command agenix -r  # Rekeys all secrets
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
```

