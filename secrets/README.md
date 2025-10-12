# Secrets Management with agenix

This directory contains encrypted secrets for the NixOS configuration using [agenix](https://github.com/ryantm/agenix).

## Setup

### On the Server (First Time)

1. Get the server's SSH host key in age format:
```bash
nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
```

2. Replace the placeholder key in `secrets.nix` with the actual host key.

### On Your Local Machine

1. Get your SSH key in age format:
```bash
ssh-add -L | ssh-to-age
```

2. Add your key to the `adminKeys` list in `secrets.nix`.

## Managing Secrets

### Creating/Editing Secrets

Use the `agenix` CLI tool to edit secrets (automatically encrypts/decrypts):

```bash
# Enter the dev shell to get agenix CLI
nix develop

# Edit a secret (creates if doesn't exist)
agenix -e cloudflare-api-token.age

# Rekey all secrets (after adding/removing keys in secrets.nix)
agenix -r
```

### Using Secrets in NixOS Config

In your NixOS modules:

```nix
{ config, ... }:
{
  age.secrets.cloudflare-api-token = {
    file = ../secrets/cloudflare-api-token.age;
    owner = "caddy";
    group = "caddy";
  };
  
  # Reference the secret in your config
  services.caddy = {
    # Use: config.age.secrets.cloudflare-api-token.path
  };
}
```

## Current Secrets

- `cloudflare-api-token.age` - Cloudflare DNS API token for Caddy ACME DNS-01 challenge
- `cloudflared-token.age` - Cloudflare tunnel token
- `vaultwarden-admin-token.age` - Vaultwarden admin authentication token
- `postgres-affine-password.age` - PostgreSQL password for Affine database

## Security Notes

- Secrets are encrypted using age encryption
- Only the server's SSH host key and authorized admin keys can decrypt
- The `.age` files are safe to commit to git
- Never commit unencrypted secrets or the private keys
- The `secrets.nix` file (public keys only) is safe to commit

