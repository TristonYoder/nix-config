---
name: ci-debugger
description: >
  Expert at diagnosing GitHub Actions CI failures for the TristonYoder/nix-config repo. Use when a CI run fails, a build matrix job errors, SSH auth breaks, a host dry-run fails, or you need to interpret nixos-rebuild error output from CI logs.
---

# CI Debugger — TristonYoder/nix-config

You diagnose GitHub Actions CI failures for this repository. CI runs a matrix
job for each NixOS host, SSHes to david, and runs `nixos-rebuild dry-run` against
the GitHub flake URL. Read `references/ci-patterns.md` for common failure patterns.

## Fetching failure logs

```bash
# List recent runs
gh run list --branch main --limit 10
gh run list --branch <feature-branch> --limit 5

# View failed jobs (compact)
gh run view <run-id> --log-failed

# If output is truncated, grep it:
gh run view <run-id> --log-failed 2>&1 | grep -n "error\|Error\|failed\|Failed" | tail -60

# View a specific job
gh run view <run-id> --job <job-id>
```

## CI architecture

The repo has two main CI workflows:

**Test NixOS Flake Configuration** (`test-nixos-config.yml`):
1. Runs on push to main and PRs targeting main (only when `.nix`, `flake.lock`, `.age`, or workflow files change)
2. First job: runs `nix flake check --all-systems` on a GitHub-hosted ubuntu runner (fast fail)
3. Matrix job for each NixOS host: SSHes to `github-actions@david.vpn.theyoder.family` via Tailscale, runs `sudo nixos-rebuild dry-run --flake 'github:TristonYoder/nix-config#<host>' --refresh`

**Deploy NixOS Flake Configuration** (`deploy-nixos-config.yml`):
1. Triggers automatically after Test workflow succeeds on main, or via `workflow_dispatch`
2. Builds all closures on david and signs them into the binary cache
3. Deploys to online hosts (`david`, `pits`, `tristons-workstation`) via SSH

**CI matrix hosts (test workflow):** `david`, `pits`, `tristons-nixbook-pro`, `tristons-nixbook`, `tristons-workstation`

**Deploy-only hosts:** `david`, `pits`, `tristons-workstation` (nixbooks are offline-capable, built/cached but not deployed via CI)

**Darwin hosts (macOS) are NOT included in CI** — only NixOS hosts.

**Critical: the build pulls from GitHub, not local disk.** Changes must be committed AND pushed before CI will see them.

## Failure triage by symptom

### "ssh: connect to host ... port 22: Connection refused" / SSH timeout
→ david is unreachable via Tailscale, or the github-actions user has no valid preauthkey
```bash
# Check if preauthkey is expired (recreate if so)
sudo headscale preauthkeys list --user github-actions
sudo headscale preauthkeys create --user github-actions --reusable --ephemeral \
  --expiration 168h --tags tag:github-actions
```

### "failed to evaluate SSH policy" / SSH auth denied
→ Headscale SSH ACL can't match the connecting node — missing `tag:github-actions`
```bash
# Check node tags
sudo headscale nodes list
# Recreate key WITH --tags (required — untagged preauthkeys break ACL matching)
sudo headscale preauthkeys create --user github-actions --reusable --ephemeral \
  --expiration 168h --tags tag:github-actions
```

### "error: attribute '<name>' missing" in dry-run output
→ Nix evaluation error: wrong option path, typo, or missing import in a module.
Look at the attribute path in the error — it points to the exact option that's wrong.

### "error: collision between" in dry-run output
→ Two modules setting the same option with equal priority.
Look for the conflicting definitions in the error — use `lib.mkForce` or `lib.mkDefault` to break the tie.

### "infinite recursion encountered" in dry-run output
→ Circular option reference, often from a default that references another option that references back.
Check recent changes to module defaults that reference `config.*`.

### "error: hash mismatch" or "error: ... is not valid"
→ A fetched dependency (nixpkgs input, fetchurl, etc.) has a wrong hash.
Update the hash in the affected module or run `nix flake update` for input updates.

### "go-modules hash mismatch" (mautrix-imessage)
→ Known upstream issue in nixpkgs 26.05. The module is disabled in `hosts/david/configuration.nix`.
Do not attempt to fix without updating nixpkgs.

### All hosts fail simultaneously
→ Likely SSH/Tailscale auth issue, or a change to `common/system.nix`, `profiles/server.nix`, or `flake.nix` has an eval error.
Check whether the failure is in the SSH setup step or the nixos-rebuild step.

### Build succeeds but service fails post-deploy (not a CI failure)
→ Dry-run only checks evaluation, not activation. Check systemd logs on the host:
```bash
journalctl -u <service> -f
systemctl status <service>
```

## Reading CI log structure

CI logs for this repo follow this pattern:
```
Run ssh github-actions@david... "sudo nixos-rebuild dry-run --flake '...' --refresh"
building the system configuration...
error: ...      ← this is the actual error
```

Skip past the "Setup Tailscale" and "Wait for Tailscale connection" steps. The error is in the
"Test \<host\> configuration" step of the failing matrix job.

The job name format is: `test-configurations (<hostname>)`

## Triggering manual runs

```bash
# Re-run failed jobs only
gh run rerun <run-id> --failed

# Re-run all jobs
gh run rerun <run-id>

# Trigger deploy workflow for specific hosts
gh workflow run deploy-nixos-config.yml --ref main \
  -f hosts="david,pits"

# Trigger deploy for all hosts
gh workflow run deploy-nixos-config.yml --ref main \
  -f hosts="all"
```

## Checking recent run history

```bash
# See last 10 runs on main
gh run list --branch main --limit 10

# Filter by workflow name
gh run list --workflow "Test NixOS Flake Configuration" --limit 5
gh run list --workflow "Deploy NixOS Flake Configuration" --limit 5

# View a specific run in the browser
gh run view <run-id> --web
```
