# GitHub Actions CI/CD

Automated testing and deployment for all NixOS hosts using GitHub Actions.

## Overview

When you push to `main`, the workflows:

1. Validate flake syntax on the GitHub Actions runner
2. Dry-run all NixOS host configurations on david (via `github:` flake URL)
3. Build closures for every NixOS host on david and sign them into the binary cache
4. Deploy to all online hosts — each host downloads pre-built paths from the cache

## Architecture

```
Push to main
    ↓
Syntax Check (runner, ~30s)
    ↓
┌──────────────────────────────────────┐
│  dry-run all hosts on david          │
│  (parallel matrix, ~2-3 min each)   │
└──────────────────────────────────────┘
    ↓ All pass
Build all closures on david + sign to binary cache
(sequential per host, ~5-20 min total)
    ↓
┌─────────────┬─────────────┬──────────────────────┐
│   david     │    pits     │  tristons-workstation │
│   DEPLOY    │   DEPLOY    │        DEPLOY         │
│  (fast, pulls from cache) │                       │
└─────────────┴─────────────┴──────────────────────┘
```

No rsync. No temp directories. Every rebuild — in CI and locally via `rebuild` — hits the binary cache.

## Managed Hosts

| Host | Type | CI Test | Auto-Deploy | Cache Build |
|------|------|---------|-------------|-------------|
| **david** | Main Server | ✅ | ✅ | ✅ |
| **pits** | Edge VPS | ✅ | ✅ | ✅ |
| **tristons-workstation** | Desktop | ✅ | ✅ | ✅ |
| **tristons-nixbook** | Laptop | ✅ | ❌ (offline) | ✅ best-effort |
| **tristons-nixbook-pro** | Laptop | ✅ | ❌ (offline) | ✅ best-effort |

## Workflows

### test-nixos-config.yml

**Triggers:** Every push and pull request

**Jobs:**
1. `check-flake-syntax` — installs nix on the runner, runs `nix flake check --all-systems`
2. `test-configurations` (matrix: all NixOS hosts) — SSHes to david via Tailscale and runs:
   ```
   sudo nixos-rebuild dry-run --flake 'github:TristonYoder/nix-config#<host>' --refresh
   ```

All tests are parallel. One failing host doesn't stop others.

### deploy-nixos-config.yml

**Triggers:**
- Automatic after `test-nixos-config.yml` succeeds on `main`
- Manual trigger (`workflow_dispatch`) with optional host selection

**Jobs:**
1. `prepare-deployment` — determines which hosts to deploy
2. `build-all-closures` — SSHes to david, builds every NixOS host toplevel from `github:`, signs the closure into `/data/nix-builds/cache`
3. `deploy-configurations` (parallel matrix) — SSHes to each online host and runs:
   ```
   sudo nixos-rebuild switch --flake 'github:TristonYoder/nix-config#<host>' --refresh
   ```
4. `deployment-summary` — reports overall status

**Closure build order within `build-all-closures`:**
- `david`, `pits`, `tristons-workstation` — must succeed (blocks deployment if any fail)
- `tristons-nixbook`, `tristons-nixbook-pro` — best-effort (logged but non-blocking)

## Usage

### Automatic Deployment

Push or merge to `main`. Tests run, then if all pass:
1. Closures built and cached on david
2. All online hosts deploy in parallel from the cache

### Manual Deployment

1. GitHub → Actions → "Deploy NixOS Flake Configuration" → Run workflow
2. Set `hosts` to `all` (default) or a comma-separated subset: `david,pits`

### Test a Feature Branch

```bash
git checkout -b feat/my-change
# make changes
git add . && git commit -m "feat: description"
git push origin feat/my-change
```

The test workflow runs dry-runs for every host. No deployment occurs on non-`main` branches.

To test a branch locally before merging:
```bash
rebuild -b feat/my-change
```

## Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `HEADSCALE_AUTHKEY` | Headscale pre-auth key (tagged `tag:github-actions`) |
| `HEADSCALE_LOGIN_SERVER` | Headscale control server URL |
| `NIXOS_SERVER_USER` | SSH user (`github-actions`) |
| `SSH_PRIVATE_KEY` | SSH private key authorized on all hosts |
| `MATRIX_HOMESERVER_URL` | Matrix homeserver URL |
| `MATRIX_ROOM_ID` | Matrix room ID (starts with `!`) |
| `MATRIX_ACCESS_TOKEN` | Matrix bot access token |

## Host Configuration

Each managed NixOS host needs:

```nix
{ modules.services.development.github-actions.enable = true; }
```

This creates the `github-actions` user with sudo access and the authorized SSH key.

## Adding a New Host

1. Create the host configuration under `hosts/<hostname>/`
2. Add it to `flake.nix` in `nixosConfigurations`
3. Add it to the test matrix in `test-nixos-config.yml`:
   ```yaml
   matrix:
     host:
       - new-hostname
   ```
4. If it should be auto-deployed, add it to `ALL_HOSTS` in `deploy-nixos-config.yml`:
   ```bash
   ALL_HOSTS='["david", "pits", "tristons-workstation", "new-hostname"]'
   ```
   And add `build_and_cache new-hostname` to the `build-all-closures` job.
5. Enable `modules.services.development.github-actions.enable = true` on the host

## Rollback

```bash
ssh github-actions@<hostname>.vpn.theyoder.family
sudo nixos-rebuild switch --rollback
# or switch to a specific generation:
sudo nixos-rebuild switch --generation N
```

## Troubleshooting

### Host unreachable

```bash
sudo tailscale status
ssh github-actions@<hostname>.vpn.theyoder.family
```

### Stale build (nix uses old flake ref)

Always include `--refresh` when using `github:` URLs. The workflows already do this.
Without it, nix may resolve the flake ref from a local cache and build a stale commit.

### Closure build fails for an offline host

`tristons-nixbook` and `tristons-nixbook-pro` failures are logged but don't block deployment.
Their closures can be rebuilt on the next push.

### See recent CI runs

```bash
gh run list --branch main --limit 5
gh run view <run-id> --log-failed
```
