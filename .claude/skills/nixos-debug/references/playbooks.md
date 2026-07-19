# Debugging Playbooks

Proven fixes for documented failure modes. Check here before diagnosing from scratch.

---

## SDDM Blinking Cursor (No Login Screen)
**Host:** david — Plasma 6 + NVIDIA

SDDM defaults to `DisplayServer=wayland`. The NVIDIA DRM driver rejects the `video=1920x1080`
kernel param set by `modules/hardware/display-resolution.nix`, causing `kwin_wayland` to
exit after ~1 second. SDDM never retries.

**Quick fix:** `sudo systemctl restart display-manager`

**Permanent fix options (not yet applied):**
- `services.displayManager.sddm.wayland.enable = false;`
- Remove the `video=` kernel param from `display-resolution.nix` (NVIDIA DRM doesn't support
  user-defined modes — only useful for simpledrm/efifb)

**Diagnostics:**
```bash
systemctl status display-manager
journalctl --grep="sddm|kwin"
journalctl --grep="nvidia.*drm"
ls /tmp/.X11-unix/    # empty = no X display running
```

---

## Qt Apps Crash on Plasma 6 Wayland (SIGABRT / exit 134)
**Host:** david — Plasma 6 Wayland + NVIDIA

Exit code 134 (SIGABRT) at `init_platform` in libQt6Gui — Qt can't find a platform
plugin. The nixpkgs dolphin-emu wrapper and some other apps hardcode
`--set QT_QPA_PLATFORM xcb`. On Wayland, XWayland starts on-demand and `DISPLAY` is
unset at that moment, so Qt aborts trying to use xcb.

**Fix applied:** `xwayland-init` systemd user service in `modules/system/desktop.nix`
forces KWin to start XWayland eagerly at login. Fixes all Qt xcb apps at once.
`environment.sessionVariables` cannot override binary wrappers that use `--set`.

**Diagnostics:**
```bash
coredumpctl list
# Journal: look for init_platform in Qt stack trace
cat $(which <app>)        # check for QT_QPA_PLATFORM hardcode
loginctl show-session <id>  # Type=wayland = no native X11
```

---

## /data NFS Automount Fails on tristons-workstation

Three interacting units: `data.automount`, `data.mount`, `nfs-david-reachable.service`.

**Ordering cycle — symptom:** `data.automount` shows `inactive (dead)` at boot.

With `DefaultDependencies=yes` (systemd default), `data.automount` is added to
`local-fs.target.wants/`. Any network dependency on the automount unit creates a cycle:
```
local-fs.target → data.automount → nfs-david-reachable →
network-online.target → ... → local-fs.target
```
systemd resolves ordering cycles by deleting the job — so the automount unit is killed.

**Fix:** `DefaultDependencies=false` in the automount's `unitConfig`. Add
`Before=umount.target remote-fs.target` and `Conflicts=umount.target` manually for
clean shutdown. Network dependency belongs on `data.mount`, not `data.automount`.

**Route-missing pings — symptom:** All pings fail in `nfs-david-reachable` logs.

`network-online.target` fires as soon as any managed interface has an IP — typically
`eno1` (`10.150.10.0/24`). The route to `10.150.100.30` lives on `enp7s0`
(`10.150.100.0/23`) which completes DHCP slightly later. `ping` exits immediately with
"Network is unreachable" when there's no route, burning all retries in milliseconds.

**Fix:** Two-phase script in `nfs-david-reachable`:
1. Poll `ip route get 10.150.100.30` up to 30s (sleep 1 between retries)
2. Ping david up to 10 times once the route exists

**`environment.etc` drop-ins don't work on `data.mount`:** NixOS's etc-builder can't
create nested subdirectories (e.g. `systemd/system/data.mount.d/`). Use `systemd.mounts`
to define the full mount unit instead.

**Diagnostics:**
```bash
systemctl status data.automount data.mount nfs-david-reachable
journalctl -b -u data.automount -u data.mount -u nfs-david-reachable
# data.automount must NOT appear here:
ls /etc/systemd/system/local-fs.target.wants/
ip route get 10.150.100.30
```

---

## "No Identity Matched" — Agenix Secret Decryption Failure

Secret was encrypted with raw `age` command (produces X25519 format) instead of
`encrypt-secret.sh` (produces ssh-ed25519 format that agenix expects).

**Diagnosis:** `./secrets/encrypt-secret.sh -v <secret>.age`
If output shows `age1...` recipients, it's X25519 — wrong format.

**Fix:** Re-encrypt with the script:
```bash
cd secrets
./decrypt-secret.sh <secret>.age > /tmp/plain.txt
./encrypt-secret.sh -n <secret>.age -f /tmp/plain.txt
rm /tmp/plain.txt
```

Never encrypt manually with `age` — always use `encrypt-secret.sh`.

---

## Headscale 0.25 Policy: Use Email as Username

headscale 0.25 requires email addresses (OIDC LoginName) in ACL/SSH policy, not
headscale usernames.

- `triston@theyoder.family` — correct (matches OIDC LoginName)
- `tristonyoder@theyoder.family` — wrong (headscale username)
- `tristonyoder@id.theyoder.family` — wrong format

Local `github-actions` user (no OIDC): `github-actions@ts.theyoder.family`

To check what LoginName headscale assigns: `sudo tailscale debug netmap | grep LoginName`

**Fix:**
```bash
sudo headscale policy get > /tmp/policy.json
# Edit: replace headscale usernames with email addresses
sudo headscale policy set -f /tmp/policy.json
```

---

## Headscale Preauthkeys Missing --tags Breaks CI SSH

Without `--tags tag:github-actions`, preauthkeys produce untagged nodes. The headscale
SSH ACL requires `tag:github-actions` as source — "failed to evaluate SSH policy" is
returned because the policy can't match (not an explicit deny).

**Always create with:**
```bash
sudo headscale preauthkeys create \
  --user github-actions --reusable --ephemeral \
  --expiration 168h --tags tag:github-actions
```

---

## nixos-install OOM on Live Installer (Swapless RAM Disk)

The live installer runs entirely in RAM with no swap by default. A heavy closure
(gaming module with Steam + 11 emulators + DaVinci Resolve) can exhaust RAM during
`nixos-install`, freezing the machine hard enough that SSH stops responding. Recovery
requires a hard power-cycle (which can corrupt the live USB, requiring a re-flash).

**Mitigations before first install:**
1. Disable heavy optional modules: `modules.services.gaming.enable = false;` (re-enable post-install)
2. Create swap on the target disk before running nixos-install:
   ```bash
   sudo btrfs filesystem mkswapfile --size 16G /mnt/swapfile
   sudo swapon /mnt/swapfile
   ```
3. `free -h` to confirm `Swap:` is non-zero before starting.

**Note:** Already-built store paths under `/mnt/nix/store` survive a reboot of the live
session as long as target disk partitions aren't reformatted — remount and resume rather
than starting over.

---

## Caddy Fixed-Output Hash Mismatch (`caddy-src-with-plugins`)

`modules/services/infrastructure/caddy.nix` builds Caddy via `pkgs.caddy.withPlugins`,
which fetches Go module sources for the pinned plugin list and checks them against a
pinned `hash`. This is a fixed-output derivation, so any change to the Go module graph
for the pinned plugin versions (a transitive dependency release, a proxy re-fetch, or a
nixpkgs bump to the `caddy` builder itself) changes the fetched content and breaks the
hash — even though `caddy.nix` itself wasn't touched.

**Symptom:**
```
error: hash mismatch in fixed-output derivation '.../caddy-src-with-plugins-....drv':
         specified: sha256-...
            got:    sha256-...
```

**Fix:** copy the `got:` value from the error directly into the `hash` field in
`caddy.nix` — the mismatch is expected drift, not a security concern, since the fetch
target (Go module proxy for the pinned `github.com/...@vX.Y.Z` plugin refs) is unchanged.
Do not use `lib.fakeSha256` as a permanent value; only the real `got` hash belongs there.
