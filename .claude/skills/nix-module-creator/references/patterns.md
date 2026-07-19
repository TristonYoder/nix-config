# Module Patterns Reference

## Canonical module template

Every service module in `modules/services/<category>/<name>.nix` follows this
structure. The `vHosts` registration at the end is **mandatory** — it is what
wires Caddy, Technitium DNS, Gatus monitoring, Homepage dashboard, and Cloudflare
Tunnel all at once. Never configure those providers directly inside a service module.

```nix
{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.<category>.<name>;
in
{
  options.modules.services.<category>.<name> = {
    enable = mkEnableOption "<Human-readable description of the service>";

    domain = mkOption {
      type = types.str;
      default = "<name>.${config.networking.domain}";
      description = "Domain for <name>.";
    };

    port = mkOption {
      type = types.port;       # use types.port, not types.int
      default = <port>;
      description = "Port <name> listens on.";
    };

    # Add service-specific options here. For secrets, always use:
    #   environmentFile = mkOption { type = types.nullOr types.path; default = null; }
    # Never embed credentials as string options.
  };

  config = mkIf cfg.enable {

    # ── Service configuration ───────────────────────────────────────────────
    # Prefer native NixOS service modules (services.<name>.enable = true).
    # Use OCI containers only when no native module exists.

    services.<name> = {
      enable = true;
      # bind to localhost — Caddy handles TLS termination
    };

    # ── vHosts registry (REQUIRED — do not omit) ────────────────────────────
    # Use the bare subdomain as key; it auto-expands to <key>.<networking.domain>.
    modules.services.vHosts.hosts."<name>" = {
      reverseProxyPort = cfg.port;
      displayName      = "<Human-readable name>";   # shown in Homepage + Gatus
      category         = "<category>";               # groups tiles in Homepage
      icon             = "<icon-slug>";              # dashicons / selfh.st slug
      # monitor = false;   # uncomment if service won't return HTTP < 500
      # public  = true;    # uncomment to expose via Cloudflare Tunnel
    };
  };
}
```

### Attribute name conventions

Nix attribute names must be valid identifiers. When a service name contains
hyphens, convert to camelCase in the option path:

| Service file | Option path |
|---|---|
| `stirling-pdf.nix` | `modules.services.productivity.stirlingPdf` |
| `open-webui.nix` | `modules.services.ai.openWebui` |
| `invoice-ninja.nix` | `modules.services.productivity.invoiceNinja` |


## Native NixOS service wrapper pattern

When wrapping an existing `services.<foo>` NixOS module, the wrapper should:
- Set sane localhost-only defaults (`host = "127.0.0.1"`, `address = "127.0.0.1"`)
- Expose only the options callers actually need; forward the rest via `extraSettings`
- Not duplicate every upstream option — let callers use `services.<foo>` directly for
  anything your typed options don't cover

Example (from `modules/services/ai/litellm.nix`):
```nix
config = mkIf cfg.enable {
  services.litellm = {
    enable           = true;
    host             = "127.0.0.1";
    port             = cfg.port;
    environmentFile  = cfg.environmentFile;
    settings         = { /* generated from typed options */ } // cfg.extraSettings;
  };

  modules.services.vHosts.hosts."litellm" = {
    reverseProxyPort = cfg.port;
    displayName      = "LiteLLM";
    category         = "ai";
    icon             = "litellm";
  };
};
```


## OCI container fallback pattern

Use this when no native NixOS module exists. The repo uses Docker as the OCI
backend (already configured on david).

```nix
config = mkIf cfg.enable {
  virtualisation.oci-containers.containers."<name>" = {
    image  = "vendor/image:latest";
    ports  = [ "127.0.0.1:${toString cfg.port}:8080" ];
    volumes = [
      "/var/lib/<name>/data:/app/data"
    ];
    environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
    environment = {
      # Non-secret env vars only — secrets go in environmentFile
      APP_URL = "https://${cfg.domain}";
    };
  };

  # Ensure data directory exists with correct ownership
  systemd.tmpfiles.rules = [
    "d /var/lib/<name>/data 0750 root root -"
  ];

  modules.services.vHosts.hosts."<name>" = {
    reverseProxyPort = cfg.port;
    displayName      = "<Name>";
    category         = "<category>";
    icon             = "<icon>";
  };
};
```

### GPU passthrough (for AI/compute containers)

When the container needs NVIDIA GPU access:
```nix
virtualisation.oci-containers.containers."<name>" = {
  extraOptions = [ "--gpus=all" "--runtime=nvidia" ];
};

# Also enable container toolkit on the host:
hardware.nvidia.container-toolkit.enable = true;  # NixOS 24.11+
```


## Secrets pattern (agenix)

### In the module
```nix
# Option declaration
environmentFile = mkOption {
  type        = types.nullOr types.path;
  default     = null;
  description = "Path to environment file with secrets. See modules/secrets.nix.";
};

# Usage in config block
services.foo.environmentFile = cfg.environmentFile;
# or for OCI:
virtualisation.oci-containers.containers.foo.environmentFiles =
  lib.optional (cfg.environmentFile != null) cfg.environmentFile;
```

### In modules/secrets.nix
```nix
age.secrets.foo-env = {
  file  = ../secrets/foo-env.age;
  owner = "foo";   # systemd service user, or "root" for OCI containers
};
```

### In the host config
```nix
modules.services.category.foo = {
  enable          = true;
  environmentFile = config.age.secrets.foo-env.path;
};
```

### Secret file format (for documentation, never commit plaintext)
```
# secrets/foo-env (encrypted with encrypt-secret.sh before commit)
APP_KEY=<random-32-char-string>
DB_PASSWORD=<password>
```

**Never** use `builtins.readFile` on a secret — it embeds the secret in the
Nix store (world-readable).


## Restart policy for custom systemd services

Any time a module defines its own `systemd.services.<name>` unit — a native
service wrapper, an init/setup oneshot, a sync job — decide its restart
behavior explicitly. Don't leave it at the systemd/NixOS default without
thinking about it: several modules in this repo (`services.github-runners`
native backend, agenix-secret-prep oneshots) default to `Restart=no`, which
means a transient failure (secret not decrypted yet, dependency not up yet,
lost network) leaves the service dead until someone notices and manually
restarts it.

Pick one of these three buckets:

**1. Long-running service (`Type = "simple"/"notify"/"exec"`) that should
always be up.**
```nix
serviceConfig = {
  Restart = "on-failure";   # or "always" if a clean exit should also restart
  RestartSec = "10s";       # backoff before retrying
};
```
Add `StartLimitBurst`/`StartLimitIntervalSec` only if repeated crashes should
eventually give up (e.g. a bad config that will never self-correct). Otherwise
leave the systemd default (5 restarts / 10s) or widen it — don't let a unit
go permanently `failed` for a condition that will resolve itself.

**2. Oneshot "gate" service — blocks a dependent unit via `before`/`requiredBy`,
and can fail on a transient condition (secret path not ready, container not
warm yet, upstream API racing with a health check).**
```nix
serviceConfig = {
  Type = "oneshot";
  RemainAfterExit = true;
  Restart = "on-failure";
  RestartSec = "10s";        # or longer if it's polling something slow
  StartLimitIntervalSec = 0; # never permanently give up — this unit blocks
                              # something else from starting; it must keep
                              # retrying until whatever broke it is fixed
};
```
Reference examples: `caddy-prepare-env` (modules/services/infrastructure/caddy.nix),
the postal setup chain (modules/services/communication/postal.nix),
`nextcloud-configure-collabora`/`nextcloud-configure-onlyoffice`.

**3. Oneshot that is NOT a candidate for `Restart=` — leave it alone.**
- Already made idempotent/non-failing (script ends in `|| true`, or checks a
  marker file and exits 0 when already done and there's nothing to retry).
- Triggered externally on a cadence that already provides retry — a
  `systemd.timers.*` companion, a udev/hotplug rule, or a `sleep.target`
  hook. Adding `Restart=` here just risks overlapping runs with the next
  scheduled trigger.
- Fails on a condition a retry can't fix (e.g. a database collation mismatch
  that needs a human to run a migration). Retrying forever just spins for no
  reason — let it fail and stay `failed` so the alert is visible.

When in doubt, ask: "if this unit fails, will retrying with a delay plausibly
succeed once the underlying blocker clears on its own?" If yes → bucket 1/2.
If no → bucket 3, and leave a comment explaining why it's intentionally not
auto-restarting.

## Category default.nix format

Every category has a `default.nix` that just lists imports:

```nix
{ ... }:
{
  imports = [
    ./service-a.nix
    ./service-b.nix
    ./new-service.nix   # ← add here, alphabetical order preferred
  ];
}
```


## Profile vs host config placement

```nix
# profiles/server.nix — for services appropriate on any server
modules.services.productivity.paperlessNgx = {
  enable = lib.mkDefault true;
};

# hosts/david/configuration.nix — for david-specific or secret-dependent services
modules.services.productivity.paperlessNgx = {
  enable          = true;
  environmentFile = config.age.secrets.paperless-env.path;
};

# hosts/tristons-workstation/configuration.nix — for GPU or workstation-only services
modules.services.ai.invokeAi = {
  enable = true;
  # no proxyHost → runs locally on the GPU
};
```


## vHosts registry — full option reference

Key = bare subdomain (auto-expands to `<key>.<networking.domain>`) or FQDN.

| Option | Type | Default | Purpose |
|---|---|---|---|
| `reverseProxyPort` | port | 80 | Upstream port for Caddy |
| `reverseProxyHost` | str | "localhost" | Upstream host (for cross-host proxying) |
| `reverseProxySSL` | bool | false | Use HTTPS upstream |
| `reverseProxyAddress` | str? | null | Full upstream URL (overrides host+port+ssl) |
| `displayName` | str | titleCase(key) | Label in Homepage + Gatus |
| `category` | str | "" | Dashboard group |
| `icon` | str | "" | dashicons / selfh.st slug |
| `monitor` | bool | true | Include in Gatus status monitoring |
| `public` | bool | false | Expose via Cloudflare Tunnel |
| `serverAliases` | [str] | [] | Extra domains for same vHost |
| `extraConfig` | lines | "" | Raw Caddy config appended to site block |
| `rawConfig` | bool | false | `extraConfig` is entire site block (no proxy template) |
| `dnsRecord` | bool | true | Create Technitium DNS record |
| `localHostsEntry` | bool | true | Add 127.0.0.1 /etc/hosts entry |


## Compliance checklist

When auditing a module, verify each item:

- [ ] Options declared under `modules.services.<category>.<name>` (not top-level)
- [ ] Port option uses `types.port`, not `types.int`
- [ ] Domain option defaults to `"<name>.${config.networking.domain}"`
- [ ] `vHosts` registration present with `reverseProxyPort`, `displayName`, `category`, `icon`
- [ ] No direct Caddy/nginx/DNS configuration inside the module
- [ ] No direct PostgreSQL database creation inside the module (use `services.postgresql.ensureDatabases` or a secret URL option)
- [ ] Secrets accepted as `types.nullOr types.path` options (never string)
- [ ] No `builtins.readFile` on secret paths
- [ ] Service binds to `127.0.0.1` (not `0.0.0.0`) — Caddy handles external access
- [ ] Module added to its category `default.nix`
- [ ] Enabled in the right layer (profile vs host config) per placement rules
- [ ] Any custom `systemd.services.<name>` unit has an explicit restart policy decision (see "Restart policy for custom systemd services") — not left at the silent `Restart=no` default without a reason

### Common violations by category

**"Configures provider directly"** — Module sets `services.caddy.virtualHosts`,
`services.technitium.records`, or `services.homepage.services` instead of
registering with `modules.services.vHosts.hosts`. Fix: remove the direct config
and add the vHosts registration.

**"Wrong secret pattern"** — Module has a `secretKey = mkOption { type = types.str; }`
and the host config has `secretKey = "abc123"`. Fix: change to
`secretKeyFile = mkOption { type = types.nullOr types.path; }` and use agenix.

**"Provider coupling"** — Module imports or `config.requires` a specific provider
(e.g., assumes Caddy). Modules must be provider-agnostic — they declare needs,
providers consume them.

**"mkDefault in module"** — `config = mkIf cfg.enable { enable = lib.mkDefault true; }`.
`mkDefault` belongs in profiles and host configs, not in module `config` blocks.


## Repo structure quick reference

```
modules/
  services/
    ai/           hermes-agent litellm ollama open-webui qdrant invoke-ai
    communication/ matrix-synapse mautrix-* pixelfed stalwart-mail wellknown
    development/  code-server github-actions kasm vscode-server
    gaming/       gaming romm
    infrastructure/ caddy cloudflared headscale postgresql tailscale technitium
                    nix-cache-server
    media/        beets feishin immich jellyfin jellyplex-watched jellyseerr
                  kavita music-dedup navidrome plex sunshine
    productivity/ actual babybuddy companion invoice-ninja linkwarden miniflux
                  n8n outline paperless-ngx stirling-pdf tandoor vaultwarden vikunja
    providers/    cloudflare-tunnel dashboard-homepage dashboard-homarr
                  dns-technitium monitoring
    storage/      nfs nextcloud/* samba syncthing zfs
    vhosts.nix    ← the registry definition itself
  secrets.nix     ← all agenix secret declarations
profiles/
  server.nix      ← mkDefault true for server-appropriate services
  desktop.nix     ← workstation defaults
hosts/<hostname>/
  configuration.nix  ← host-specific enables and secret wiring
```
