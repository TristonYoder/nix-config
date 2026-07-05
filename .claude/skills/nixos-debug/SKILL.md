---
name: nixos-debug
description: >
  Expert NixOS debugger for the TristonYoder/nix-config repo. Use when a build fails, a service won't start, a systemd unit is broken, there's a display/GPU issue, NFS won't mount, or CI is failing. Knows all documented failure modes and their fixes.
---

# NixOS Debugger — TristonYoder/nix-config

You diagnose and fix NixOS build failures, service startup issues, and system-level
problems in this repository. Read `references/playbooks.md` which contains the full
documented failure modes and their proven fixes — always check it before proposing
solutions to known issues.

## Triage flow

### Build failures (nix flake / nixos-rebuild)

```bash
# Always try --show-trace first
sudo nixos-rebuild build --flake . --show-trace 2>&1 | tail -80

# For evaluation errors (wrong type, missing option)
nix flake check --no-build 2>&1 | head -60

# Check if it's a specific host
sudo nixos-rebuild build --flake .#<host> --show-trace
```

Common build error patterns:
- `error: attribute '<name>' missing` — wrong option path or typo in host config
- `error: infinite recursion` — circular mkDefault / option reference
- `error: value is ... while a ... was expected` — wrong type (e.g. string where list expected)
- `error: collision between` — two modules setting the same option with equal priority

### Service not starting

```bash
systemctl status <service>                    # exit code + last few lines
journalctl -u <service> -n 100 --no-pager    # full recent log
journalctl -u <service> -f                   # follow live
journalctl -b -p err                          # all errors this boot
```

Always check:
1. Is the package actually installed? (`which <binary>`, `systemctl cat <service>`)
2. Does the service user exist? (`id <user>`)
3. Are required directories present with correct permissions?
4. Are secrets decrypted? (`ls -la /run/agenix/`)

### Agenix / secrets failures

```bash
systemctl status agenix
journalctl -u agenix -n 50
ls -la /run/agenix/
# Verify secret format (must show ssh-ed25519, not age1...)
cd /path/to/repo/secrets && ./encrypt-secret.sh -v <secret>.age
```

X25519-encrypted secrets (encrypted with raw `age` instead of `encrypt-secret.sh`) cause
"no identity matched" errors. See playbooks.md for the re-encryption procedure.

### Display / GPU issues (david — Plasma + NVIDIA)

See playbooks.md for "SDDM Blinking Cursor" and "Qt Apps Crash SIGABRT".

```bash
systemctl status display-manager
journalctl --grep="sddm|kwin|nvidia"
ls /tmp/.X11-unix/     # empty = no X display running
coredumpctl list       # Qt crashes leave coredumps
```

### NFS mount failures (tristons-workstation)

See playbooks.md for "/data NFS Automount Fails".

```bash
systemctl status data.automount data.mount nfs-david-reachable
journalctl -b -u data.automount -u data.mount -u nfs-david-reachable
ip route get 10.150.100.30    # must succeed before NFS can mount
ls /etc/systemd/system/local-fs.target.wants/  # data.automount must NOT be here
```

### CI failures (GitHub Actions)

```bash
# List recent runs
gh run list --branch main --limit 5

# Fetch failed job logs
gh run view <run-id> --log-failed
```

The CI matrix runs per-host `nixos-rebuild dry-run` jobs via SSH to david. Common causes:
- Config evaluation error (nix type mismatch, missing attribute)
- Agenix secret not re-encrypted for new host key
- Headscale preauthkey missing `--tags tag:github-actions`

See playbooks.md for headscale-specific CI SSH failures.

## Remote debugging from macOS

```bash
# SSH to target host and run diagnostics
ssh tristonyoder@david.vpn.theyoder.family "journalctl -u <service> -n 50"

# Dry-run a config change before applying
ssh github-actions@david.vpn.theyoder.family \
  "sudo nixos-rebuild dry-run --flake 'github:TristonYoder/nix-config#david' --refresh"

# Test a feature branch on a specific host
ssh github-actions@david.vpn.theyoder.family \
  "sudo nixos-rebuild dry-run --flake 'github:TristonYoder/nix-config/<branch>#<host>' --refresh"
```

Always push the branch before running remote builds — the builder fetches from GitHub, not
local disk. `--refresh` is required to avoid stale cached flake resolution.

## Port conflicts

```bash
sudo ss -tulpn | grep <PORT>
# Override in module options if needed:
modules.services.category.servicename.port = 8081;
```

## When you find a known issue

Check `references/playbooks.md` first. If the issue matches a documented failure mode,
apply the documented fix directly. If it's a new failure mode, diagnose fully and add it
to playbooks.md as part of the resolution so future sessions benefit.
