# installer - Barebones Tailscale/SSH Installer Images

Generic NixOS live install media (x86_64/aarch64 ISOs, plus a Raspberry Pi 5
sdImage) for remotely installing new hosts. No authkey or host-specific
drivers are baked in — it boots, joins your headscale tailnet, and gives you
a key-only SSH shell to drive `nixos-install` from anywhere.

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

Five flake outputs today — three ISO/sdImage builds, plus two netboot
builds for PXE (see "PXE netboot" below):

| Output | Architecture | Output | Base |
|---|---|---|---|
| `nixosConfigurations.installer` | x86_64-linux | `nixos-installer-x86_64.iso` | `installation-cd-minimal.nix` |
| `nixosConfigurations.installer-aarch64` | aarch64-linux | `nixos-installer-aarch64.iso` | `installation-cd-minimal.nix` |
| `nixosConfigurations.installer-rpi5` | aarch64-linux (Raspberry Pi 5 / CM5) | `nixos-installer-rpi5.img.zst` | `nixos-raspberrypi` flake (`raspberry-pi-5.base`) |
| `nixosConfigurations.installer-netboot` | x86_64-linux | `netbootBundle` (kernel + initrd + iPXE script) | `netboot-minimal.nix` |
| `nixosConfigurations.installer-netboot-aarch64` | aarch64-linux | `netbootBundle` | `netboot-minimal.nix` |

The netboot outputs share [common.nix](common.nix) with the ISO builds — see
[netboot.nix](netboot.nix). Pi 5 has no netboot output: it network-boots via
its own EEPROM/TFTP mechanism (no iPXE chainload involved), which is a
materially different implementation not covered here.

`installer-rpi5` needs its own base — generic aarch64 UEFI ISOs don't boot on
the Pi 5, it needs Pi-specific firmware/bootloader/kernel handling. See
[rpi5.nix](rpi5.nix) and [common.nix](common.nix) (the Tailscale/SSH/QR logic
all three variants share).

**Naming gotcha (cost real debugging time, documented so it doesn't happen
again):** `isoImage.isoName` / `image.fileName` do **not** control the real
output filename for the `cd-dvd`-based ISO builder in this nixpkgs snapshot —
setting them has zero effect on the actual file under
`system.build.isoImage`'s `iso/` subdir, confirmed by building both ways. The
option that's actually load-bearing is `isoImage.isoBaseName` (used in
`configuration.nix`). The Pi 5 sdImage builder doesn't have this problem —
`sdImage.imageBaseName` (in `rpi5.nix`) works as documented.

## CI: automatic rebuilds

[`.github/workflows/build-installer-iso.yml`](../../.github/workflows/build-installer-iso.yml)
builds and publishes all five images (ISO x86_64/aarch64/rpi5 to
`/data/nix-iso`, netboot x86_64/aarch64 to `/data/nix-pxe`) on david whenever
something that actually changes their contents lands on `main`:
`hosts/installer/**`, `modules/system/users.nix` (the baked-in SSH key), or
`flake.nix`. Every other push is a no-op for this workflow — it doesn't run
on a schedule or on every commit.

It builds x86_64 natively; aarch64 and rpi5 via QEMU emulation
(`boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` in
`hosts/david/configuration.nix` — added specifically so CI, which can only
reach david, doesn't depend on a personal Mac being online). rpi5's custom
kernel (`linux_rpi-bcm2712`) doesn't build under emulation — a
HOSTCC-vs-target-binary mismatch in its kconfig step (confirmed:
`Exec format error` trying to run the emulated `rm`/`sed` as native
build-time tools) — so david also trusts `nixos-raspberrypi`'s own binary
cache (`nixos-raspberrypi.cachix.org`, also in `hosts/david/configuration.nix`)
and fetches the prebuilt kernel instead of compiling it. Each image is
written under a `.new` suffix and `mv`'d into place, so Caddy never serves a
half-written file mid-build.

Trigger a manual rebuild any time from the Actions tab ("Build Installer
Images" → Run workflow), or:

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

### Raspberry Pi 5

```bash
nix build '.#nixosConfigurations.installer-rpi5.config.system.build.sdImage' --refresh
```

Works the same way from david (emulation + `nixos-raspberrypi.cachix.org` for
the kernel — see CI section above) or from `tyoder-mbp`'s native
`linux-builder` (no cache dependency, but slower to iterate since nothing's
pre-built). The result is a directory; the actual `.img.zst` file is under
`<out-link>/sd-image/`.

### Netboot (PXE) bundle

```bash
nix build '.#nixosConfigurations.installer-netboot.config.system.build.netbootBundle' --refresh
# or installer-netboot-aarch64 — same emulation/linux-builder options as aarch64 above
```

The result is a directory containing `bzImage`, `initrd`, and `netboot.ipxe`
— publish all three together into `/data/nix-pxe/x86_64/` (or `aarch64/`) on
david. `netboot.ipxe` references the other two by relative filename, so they
must stay siblings.

## Downloading a pre-built image

All three variants are hosted on david at **https://nix-iso.theyoder.family/**
(internal-only — LAN/tailnet, per Caddy's default `@internal` restriction; not
reachable from the public internet) — a plain directory listing served
straight out of `/data/nix-iso`, a ZFS dataset (`data/nix-iso`) created for
this purpose. CI keeps this current automatically (see above) — no manual
rebuild/upload needed unless you're testing an unmerged change.

## Using it

1. Flash the image to a USB drive (`installer`/`installer-aarch64`) or SD
   card/NVMe (`installer-rpi5`, e.g. via `dd` or Raspberry Pi Imager's
   "custom image" option) and boot the target machine from it.
2. Watch the console (or `ssh` in once you know the tailnet IP/hostname) for
   the QR code / login URL, and authorize the node from another device.
3. Once it shows up in the tailnet (`ssh admin@ts.theyoder.family` or the
   headscale admin UI), SSH in: `ssh root@nixos-installer.<tailnet-domain>`
   (`nixos-installer-rpi5` for the Pi 5 variant).
4. From there, drive the install remotely — partition, format,
   `nixos-generate-config`, `nixos-install --flake
   github:TristonYoder/nix-config#<hostname>` — per the remote-install
   workflow in the `host-provisioner` skill.

## PXE netboot — no USB stick required

Any PXE-capable x86_64 or aarch64 client on **VLAN 10 (User Devices,
`10.150.10.0/24`)** can netboot straight into the installer, served by
`modules.services.infrastructure.pxeBoot` on david (`enp4s0f1`, tagged VLAN
10, `10.150.10.30`). See
[`modules/services/infrastructure/pxe-boot.nix`](../../modules/services/infrastructure/pxe-boot.nix)
for the dnsmasq proxyDHCP/TFTP config. Pi 5 is **not** covered — it needs its
own EEPROM/TFTP boot flow, unrelated to iPXE chainloading.

**david only answers proxyDHCP/TFTP requests on VLAN 10.** UniFi still owns
real DHCP for that network — david never hands out IP leases, it only
answers the PXE-specific boot-file questions a client asks in parallel with
its normal DHCP request. This is a one-time UniFi change, done manually
(not scripted — infrequent, low value to automate, real risk of a
self-inflicted DHCP outage on the wrong network if scripted against the
wrong target):

1. **UniFi Network app → Settings → Networks → (the VLAN 10 / User Devices
   network) → DHCP.**
2. Set these two options under "DHCP Option 66/67" (or the equivalent
   advanced DHCP fields, depending on controller version):
   - **Option 66 (TFTP server name):** `10.150.10.30` — david's `vlan10` IP.
   - **Option 67 (bootfile name):** `undionly.kpxe` — the BIOS chainload
     binary. **Leave this as the single BIOS filename, even though UEFI and
     aarch64 clients exist.** UniFi's DHCP option 67 is a single static
     value with no per-client-architecture logic. Getting UEFI/aarch64
     clients the *correct* loader (`ipxe-x86_64.efi` / `ipxe-aarch64.efi`)
     is exactly why dnsmasq runs in **proxyDHCP** mode alongside UniFi's
     real DHCP: proxyDHCP answers the PXE-specific option-93
     (client-architecture) query itself and overrides the bootfile per
     client, so UniFi's single static value only actually matters as a
     fallback for clients that don't get a proxyDHCP answer in time. Legacy
     BIOS is the safest fallback value.
   - If your controller only exposes one plain "TFTP Server" / "Boot
     Filename" field pair rather than named "Option 66/67", these are the
     same setting under a different label.
3. Save and apply. No reboot of UniFi devices needed — new DHCP option
   values take effect on the next client DHCP transaction.
4. **Verify:** boot a spare PXE-capable machine on VLAN 10 and watch it
   reach the iPXE boot menu / installer. If it hangs at "PXE-E51: No DHCP or
   proxyDHCP offers were received," double check david's `vlan10` interface
   is up (`ip a show vlan10` on david) and that the UniFi switch port
   `enp4s0f1` is plugged into is still trunking VLAN 10.
