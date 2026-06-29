# Common CI Failure Patterns

## Pattern: All hosts fail simultaneously

Usually means:
1. SSH/Tailscale auth broke (preauthkey expired, ACL policy issue)
2. A change to `common/system.nix`, `profiles/server.nix`, or `flake.nix` has an eval error
3. nixpkgs input has a breaking change (check `nix flake update` + upstream CHANGELOG)

Check: is the failure in the SSH setup step or the nixos-rebuild step?
- SSH step failure → Tailscale/auth issue
- nixos-rebuild step failure → Nix eval error in shared code

---

## Pattern: One specific host fails

Usually means:
1. That host's `configuration.nix` has an eval error (wrong option, missing import)
2. A module enabled only on that host has a bug
3. Hardware-specific option not supported by that nixpkgs version

The error message will contain the option path — trace it back to the source file.

---

## Pattern: "error: ... is not in the Nix store" after flake update

A module uses `builtins.fetchurl` or similar with a hardcoded hash that changed.
Update the hash:
```bash
nix-prefetch-url <url>
# or
nix store prefetch-file <url>
```

---

## Pattern: CI was green, then failed after a merge to main

A merge conflict was resolved incorrectly, or two PRs that individually passed
conflict when combined. Compare the failing diff against main:
```bash
git diff main...<branch> -- modules/ hosts/ profiles/
```

---

## Pattern: "go-modules hash mismatch" (mautrix-imessage)

Known issue: the go module dependencies hash for mautrix-imessage in nixpkgs 26.05
doesn't match. The module is disabled in `hosts/david/configuration.nix`.
Do not attempt to fix without updating nixpkgs — the issue is upstream.

---

## Pattern: Deploy workflow fails, test workflow passed

The deploy workflow (`deploy-nixos-config.yml`) does more than dry-run — it actually
builds and activates. Build failures here mean the closure couldn't be built or
signed into the binary cache on david. Check:
1. Is david's disk full? (`df -h /data` on david)
2. Is the agenix signing key accessible? (`ls /run/agenix/nix-cache-signing-key`)
3. Did the build OOM? (check dmesg on david for OOM killer entries)

---

## GitHub Actions workflow structure

Two main workflow files in `.github/workflows/`:

**`test-nixos-config.yml`** — runs on PRs and pushes to main:
1. `check-flake-syntax` — runs `nix flake check --all-systems` on ubuntu runner
2. `test-configurations` — matrix job per host, SSHes to david for dry-run

**`deploy-nixos-config.yml`** — runs after test passes on main, or via dispatch:
1. `prepare-deployment` — determines which hosts to deploy
2. `build-all-closures` — builds all host closures on david, signs into binary cache
3. `deploy-configurations` — switches online hosts (david, pits, tristons-workstation)
4. `notify-workstations` — pings offline workstations to check for updates

**Host matrix in test workflow:**
- `david`, `pits`, `tristons-nixbook-pro`, `tristons-nixbook`, `tristons-workstation`
- Installer ISOs (`tristons-nixbook-pro-installer*`) are NOT tested — they're build artifacts, not deployed hosts

**Darwin hosts (macOS) are NOT in CI** — only NixOS hosts are dry-run tested.
Darwin configs are only validated when `darwin-rebuild build` is run manually.

---

## Pattern: "Tailscale connection" step hangs or times out

The workflow waits 10 seconds after Tailscale auth before SSHing to david. If david's
Tailscale daemon is down or the headscale server is unreachable, all matrix jobs fail
at the SSH step (not the nixos-rebuild step).

Check headscale status on david:
```bash
sudo systemctl status headscale   # if david IS the headscale server
sudo tailscale status             # on any node
```
