---
name: nix-module-creator
description: >
  Expert NixOS module author for the TristonYoder/nix-config repository.
  Use this skill whenever the task involves: creating a new service module,
  auditing existing modules for convention violations, migrating a docker-compose
  service to a proper nix module, or updating modules when repo patterns evolve.
  Also use when asked to "add a service", "make a module for X", "convert this
  compose file", or "check if modules follow the pattern". Knows the vHosts
  registry, provider model, agenix secret pattern, OCI container fallback, and
  profile vs host-config placement rules.
---

# NixOS Module Expert — TristonYoder/nix-config

You are an expert in creating and auditing NixOS modules for this specific
repository. Read `references/patterns.md` before writing any code — it contains
the canonical module template, the full vHosts schema, the OCI fallback pattern,
the agenix secret pattern, and the compliance checklist.

## Workflow

### Creating a new module

1. **Identify the service category** (`media`, `productivity`, `ai`,
   `infrastructure`, `communication`, `storage`, `development`, `gaming`).

2. **Check nixpkgs first** — many services have native NixOS modules:
   ```bash
   nix search nixpkgs <name> 2>/dev/null | grep -i "^\\* nixpkgs"
   nix eval nixpkgs#nixosModules --apply 'x: builtins.attrNames x' 2>/dev/null \
     | tr ',' '\n' | grep -i <name>
   ```
   Native modules are strongly preferred. OCI containers are a fallback, not a default.

3. **Read one reference module** in the same category before writing:
   - Simple service (no secrets): `modules/services/media/navidrome.nix`
   - Complex native module wrapper: `modules/services/ai/litellm.nix`
   - OCI container with secrets: any module using `virtualisation.oci-containers`

4. **Read the category `default.nix`** to see the import list format.

5. **Write the module** following the canonical template in `references/patterns.md`.

   If the module defines any of its own `systemd.services.<name>` units
   (init/setup scripts, sync jobs, a native runner wrapper, etc.), choose a
   restart policy for each — see "Restart policy for custom systemd services"
   in `references/patterns.md`. Do not leave a unit that can fail on a
   transient condition at the default `Restart=no`/no-retry-limit-reset
   behavior without a documented reason.

6. **Add the import** to `modules/services/<category>/default.nix`.

7. **Enable it** — see "Placement rules" below.

8. **Validate** — run `nix flake check --no-build 2>&1 | head -60` and fix errors.

### Auditing existing modules

Run the compliance checklist from `references/patterns.md` against each module.
Common violations to look for:
- Missing `vHosts` registration (module configures Caddy directly instead)
- Wrong option type (`types.int` instead of `types.port` for port options)
- Secrets embedded in plaintext rather than via agenix path options
- `mkDefault` misuse in the wrong layer (see Placement rules)
- Module configures Caddy/nginx/PostgreSQL/ZFS directly instead of declaring intent

### Updating modules when patterns change

When a repo-wide convention changes (e.g., `appData` module replaces hardcoded
data directories, or a new provider is introduced):

1. Identify all modules affected: `grep -r "old-pattern" modules/services/`
2. Apply the new pattern consistently across all affected files
3. Update `references/patterns.md` to reflect the new norm
4. Commit in one PR per pattern change (not per module)

## Placement rules

| Condition | Where to enable |
|---|---|
| Service makes sense on every server | `profiles/server.nix` with `lib.mkDefault true` |
| Service is workstation-only | `profiles/desktop.nix` or specific host config |
| Service requires secrets to be created first | Enable in host config (not profile default) — or enable in profile but add an `assertions` guard |
| Service is GPU-dependent | Specific host config only |

**Never** put `mkDefault` inside a module's own `config` block. `mkDefault` is
for profiles and host configs to signal "default unless overridden."

## Secrets pattern

When a service needs runtime secrets (API keys, database passwords, app secrets):

1. Declare a typed option: `environmentFile = mkOption { type = types.nullOr types.path; default = null; }`.
2. Pass it to the service: `services.foo.environmentFile = cfg.environmentFile;` or
   `virtualisation.oci-containers.containers.foo.environmentFiles = [ cfg.environmentFile ];`
3. Register the secret stub in `modules/secrets.nix`:
   ```nix
   age.secrets.foo-env = { file = ../secrets/foo-env.age; };
   ```
4. Wire it in the host config:
   ```nix
   modules.services.category.foo.environmentFile = config.age.secrets.foo-env.path;
   ```
5. Never hardcode credentials anywhere in the module. Never use `builtins.readFile`
   on a secret file — that embeds the secret in the Nix store.

## Reference files

- `references/patterns.md` — canonical templates, vHosts schema, compliance checklist
