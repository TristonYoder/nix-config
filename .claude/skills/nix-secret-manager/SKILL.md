---
name: nix-secret-manager
description: >
  Expert at the agenix secrets workflow for the TristonYoder/nix-config repo. Use when encrypting new secrets, re-encrypting for new hosts, declaring secrets in secrets.nix, wiring into modules, or diagnosing "no identity matched" decryption errors.
---

# Nix Secret Manager — TristonYoder/nix-config

You manage secrets encrypted with agenix (SSH public key encryption) in this repository.
The repo is public on GitHub — every secret must be encrypted before committing.

## The golden rule

ALWAYS use `secrets/encrypt-secret.sh` to encrypt. NEVER use raw `age` commands.
The script uses `-R` (SSH recipient format) which produces `ssh-ed25519` recipients.
Raw `age` commands produce `X25519` recipients which fail to decrypt on hosts with "no identity matched".

## Full lifecycle

### 1. Encrypt a new secret

```bash
cd secrets
export PATH="/nix/var/nix/profiles/default/bin:$PATH"  # macOS only

# Interactive (prompts for value)
./encrypt-secret.sh -n my-secret.age -e

# From a file
./encrypt-secret.sh -n my-secret.age -f /tmp/plain.txt && rm /tmp/plain.txt
```

### 2. Declare in modules/secrets.nix

```nix
age.secrets.my-secret = {
  file  = ../secrets/my-secret.age;
  owner = "servicename";   # user the service runs as; "root" for OCI containers
  group = "servicename";   # optional
  mode  = "0400";          # optional, default is 0400
};
```

### 3. Reference in a module

```nix
# In the module's options:
environmentFile = mkOption { type = types.nullOr types.path; default = null; };

# In the host config that enables the service:
modules.services.category.foo.environmentFile = config.age.secrets.my-secret.path;
```

The path resolves to `/run/agenix/my-secret` at runtime — never in the Nix store.

### 4. Re-encrypt when adding a new host

When a new host is added to the repo, existing secrets that the host needs must be re-encrypted to include its SSH host key:

```bash
cd secrets
# Decrypt the existing secret
./decrypt-secret.sh existing-secret.age > /tmp/plain.txt
# Re-encrypt (script fetches all current host keys automatically)
./encrypt-secret.sh -n existing-secret.age -f /tmp/plain.txt
rm /tmp/plain.txt
```

The script reads recipient keys from `secrets/secrets.nix` `publicKeys` list, which includes all managed host SSH keys.

### 5. Verify recipient format (should show ssh-ed25519, not X25519)

```bash
./encrypt-secret.sh -v my-secret.age
```

If output shows `age1...` (X25519) recipients, the secret was encrypted with raw age and must be re-encrypted with the script.

## Diagnosing "no identity matched"

This error at boot means agenix cannot decrypt a secret with any available SSH identity.

1. Run `./encrypt-secret.sh -v the-secret.age` — check for X25519 recipients (the most common cause)
2. Check that the host's SSH key is in the `publicKeys` list in `secrets/secrets.nix`
3. Verify the host's SSH private key is present at the path agenix expects (`/etc/ssh/ssh_host_ed25519_key` by default)
4. Verify the secret is declared in `modules/secrets.nix` (not just `secrets/secrets.nix`)
5. Check `age.identityPaths` in the NixOS config — it must point to an accessible key

If re-encryption is needed:
```bash
cd secrets
./decrypt-secret.sh broken-secret.age > /tmp/plain.txt
./encrypt-secret.sh -n broken-secret.age -f /tmp/plain.txt
rm /tmp/plain.txt
# Commit and push, then rebuild the affected host
```

## Never do these

- `age -e -r ...` or `age-keygen` — produces X25519 format, causes "no identity matched"
- `builtins.readFile "/run/agenix/secret"` — embeds secret value in Nix store (world-readable)
- Hardcode credentials as Nix string options (e.g., `password = "hunter2"`)
- Commit plaintext to the repo, even temporarily (the repo is public on GitHub)
- Use `types.str` for options that will hold file paths to secrets — use `types.nullOr types.path`

## secrets/secrets.nix recipient structure

```nix
# secrets/secrets.nix
let
  # Host SSH public keys (fetched with: ssh-keyscan -t ed25519 <host>)
  david        = "ssh-ed25519 AAAA...";
  workstation  = "ssh-ed25519 AAAA...";
  tristonyoder = "ssh-ed25519 AAAA...";  # user key for admin access

  allHosts     = [ david workstation ];
  admin        = [ tristonyoder ];
in {
  "my-secret.age".publicKeys = allHosts ++ admin;
}
```

## Adding secrets for a new host

When adding a brand new NixOS host to the repo:

1. Get the host's SSH public key: `ssh-keyscan -t ed25519 <hostname-or-ip>`
2. Add the key as a variable in `secrets/secrets.nix`
3. Add it to the `publicKeys` list of every secret the new host needs
4. Re-encrypt each of those secrets (decrypt → re-encrypt with script)
5. Commit the updated `.age` files

Only include secrets a host actually needs — don't add every host to every secret's recipient list without reason.

## Module pattern: wiring a secret into a service

```nix
# modules/services/category/myservice.nix
{ config, lib, pkgs, ... }:
with lib;
let cfg = config.modules.services.category.myservice;
in {
  options.modules.services.category.myservice = {
    enable = mkEnableOption "My Service";
    # Use path, not str — this will point to /run/agenix/...
    environmentFile = mkOption {
      type    = types.nullOr types.path;
      default = null;
      description = "Path to a file containing environment variable secrets.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.myservice = {
      serviceConfig = mkIf (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
```

Then in the host config:
```nix
modules.services.category.myservice = {
  enable = true;
  environmentFile = config.age.secrets.myservice-env.path;
};
```

And in `modules/secrets.nix`:
```nix
age.secrets.myservice-env = {
  file  = ../secrets/myservice-env.age;
  owner = "myservice";
};
```
