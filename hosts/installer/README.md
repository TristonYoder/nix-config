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

## Building

There are two flake outputs — build the one matching the target machine's CPU:

| Output | Architecture | Builder |
|---|---|---|
| `nixosConfigurations.installer` | x86_64-linux | any x86_64-linux host (e.g. david) |
| `nixosConfigurations.installer-aarch64` | aarch64-linux | needs an aarch64-linux builder (see below) |

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

No host in the fleet is natively aarch64-linux, and david has no QEMU binfmt
emulation configured. The supported path is nix-darwin's built-in
`linux-builder` VM, enabled on `tyoder-mbp` (Apple Silicon) — it builds
`aarch64-linux` **natively**, no emulation needed:

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

Both variants are also hosted on david at **https://nix-iso.theyoder.family/**
(internal-only — LAN/tailnet, per Caddy's default `@internal` restriction; not
reachable from the public internet) — a plain directory listing served
straight out of `/data/nix-iso`, a ZFS dataset (`data/nix-iso`) created for
this purpose. Rebuild and re-upload after any change to
`hosts/installer/configuration.nix`; nothing regenerates this automatically.

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
