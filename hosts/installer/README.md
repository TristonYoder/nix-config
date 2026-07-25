# installer - Barebones Tailscale/SSH Installer ISO

Generic, hardware-agnostic NixOS live ISO for remotely installing new hosts. No
authkey or hardware drivers are baked in — it boots, joins your headscale
tailnet, and gives you a key-only SSH shell to drive `nixos-install` from
anywhere.

## Overview

- **Config**: [`configuration.nix`](configuration.nix)
- **Base**: `installation-cd-minimal.nix` (no GUI, no host-specific hardware modules)
- **Auth**: key-only SSH (root, `PasswordAuthentication = false`) using the
  same public key committed in [`modules/system/users.nix`](../../modules/system/users.nix)
- **Networking**: `tailscale-autoconnect` runs `tailscale up
  --login-server=https://ts.theyoder.family --ssh` on boot. Since no authkey
  is embedded (this repo is public), it prints the headscale login URL as
  text and as a scannable QR code — open/scan it on another device to
  authorize the node into the tailnet. That output is cached to
  `/run/tailscale-qr.txt` and re-printed on every shell start
  (`environment.interactiveShellInit`), so it's still visible once the boot
  log has scrolled past and you're sitting at the console prompt.

## Flake outputs

There are two flake outputs today, each producing a clearly-labeled ISO
(`nixos-installer-<arch>.iso`, via the `archLabel` let-binding in
`configuration.nix`):

| Output | Architecture | ISO filename |
|---|---|---|
| `nixosConfigurations.installer` | x86_64-linux | `nixos-installer-x86_64.iso` |
| `nixosConfigurations.installer-aarch64` | aarch64-linux | `nixos-installer-aarch64.iso` |

A future Raspberry Pi target would need a separate `sdImage`-based output
(RPi boots from an SD card image via U-Boot, not a generic UEFI ISO — a
materially different build, not just a rename) — e.g.
`nixosConfigurations.installer-rpi` producing `nixos-installer-rpi.img`,
following the same naming convention.

## CI: automatic rebuilds

[`.github/workflows/build-installer-iso.yml`](../../.github/workflows/build-installer-iso.yml)
builds and publishes both ISOs to `/data/nix-iso` on david whenever something
that actually changes their contents lands on `main`: `hosts/installer/**`,
`modules/system/users.nix` (the baked-in SSH key), or `flake.nix`. Every
other push is a no-op for this workflow — it doesn't run on a schedule or on
every commit.

It builds x86_64 natively and aarch64 via QEMU emulation
(`boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` in
`hosts/david/configuration.nix` — added specifically so CI, which can only
reach david, doesn't depend on a personal Mac being online). Each ISO is
written under a `.new` suffix and `mv`'d into place, so Caddy never serves a
half-written file mid-build.

Trigger a manual rebuild any time from the Actions tab ("Build Installer
ISOs" → Run workflow), or:

```bash
gh workflow run build-installer-iso.yml
```

## Building manually

### x86_64 (from any NixOS x86_64-linux host, e.g. david)

```bash
nix build '.#nixosConfigurations.installer.config.system.build.isoImage' --refresh
```

Or remotely from macOS, without SSHing in first:

```bash
ssh github-actions@david.vpn.theyoder.family \
  "nix build 'github:TristonYoder/nix-config#nixosConfigurations.installer.config.system.build.isoImage' --refresh --out-link /tmp/installer-iso-result --print-out-paths"
```

The result is a directory; the actual `.iso` file is under `<out-link>/iso/`.

### aarch64 (Raspberry Pi / ARM boards)

Two options:

- **On david** (same path CI uses): `boot.binfmt.emulatedSystems` makes it a
  normal cross-build via QEMU emulation —
  `nix build '.#nixosConfigurations.installer-aarch64.config.system.build.isoImage' --refresh`.
  Slower than native (emulated), but needs nothing extra set up.
- **On `tyoder-mbp`** (Apple Silicon): nix-darwin's built-in `linux-builder`
  VM builds `aarch64-linux` **natively**, no emulation:

  ```nix
  # hosts/tyoder-mbp/configuration.nix
  nix.linux-builder.enable = true;
  ```

  After a `darwin-rebuild switch` picks that up (first boot spins up the VM,
  which takes a minute or two — check with `sudo launchctl list | grep
  linux-builder`), build from that Mac:

  ```bash
  sudo nix build '.#nixosConfigurations.installer-aarch64.config.system.build.isoImage' --refresh
  ```

  `sudo` is required because the linux-builder SSH key lives in a root-only
  path (`/etc/nix/builder_ed25519`). Nix automatically dispatches the build to
  the VM via `/etc/nix/machines` — no `--builders` flag needed.

## Downloading a pre-built ISO

Both variants are hosted on david at **https://nix-iso.theyoder.family/**
(internal-only — LAN/tailnet, per Caddy's default `@internal` restriction; not
reachable from the public internet) — a plain directory listing served
straight out of `/data/nix-iso`, a ZFS dataset (`data/nix-iso`) created for
this purpose. CI keeps this current automatically (see above) — no manual
rebuild/upload needed unless you're testing an unmerged change.

## Using it

1. Flash the ISO to a USB drive and boot the target machine from it.
2. Watch the console (or `ssh` in once you know the tailnet IP/hostname) for
   the QR code / login URL, and authorize the node from another device.
3. Once it shows up in the tailnet (`ssh admin@ts.theyoder.family` or the
   headscale admin UI), SSH in: `ssh root@nixos-installer.<tailnet-domain>`.
4. From there, drive the install remotely — partition, format,
   `nixos-generate-config`, `nixos-install --flake
   github:TristonYoder/nix-config#<hostname>` — per the remote-install
   workflow in the `host-provisioner` skill.
