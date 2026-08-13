# stage-plotiphar - Signage Kiosk

Raspberry Pi 5 (Compute Module 5 Lite, PoE, onboard NVMe SSD) driving venue
displays with the [stage-plotifer](https://plotiphar.com) app.

## Overview

- **Profile**: kiosk (`profiles/kiosk.nix`)
- **Architecture**: aarch64-linux (Raspberry Pi 5 / CM5)
- **Display**: one fullscreen Chromium instance per connected HDMI output
  (up to 2, one per micro-HDMI port), managed by
  `modules.services.kiosk.browserKiosk` (see `modules/services/kiosk/browser-kiosk.nix`)
- **Reset**: the onboard power button clears all instances' cookies/cache
  and reloads them to the pairing URL instead of shutting the machine down

## How the kiosk stays paired across reboots

The stage-plotifer app pairs a display at `https://plotiphar.com/pair`: a
4-digit code, approved from an authenticated session, sets a long-lived
session cookie and redirects to `/screens/<id>`. That pairing flow itself
doesn't survive a reboot on its own — reloading `/pair` always mints a new
code regardless of an existing cookie. `kiosk-url-tracker.service` watches
each Chromium instance's DevTools port, and whenever the active tab is a
`/screens/*` URL, persists it to `/var/lib/kiosk/profile-<output>/current-url`.
`kiosk-launcher.service` reads that file back in on the next boot and opens
straight to it — only falling back to `/pair` the first time, or after a
manual reset.

## First install (physical, one-time)

`nixos-anywhere`'s kexec install path does **not** work on Raspberry Pi
boards (confirmed via the `nixos-raspberrypi` flake's own docs — the
generic kexec image has no Pi 5/bcm2712 firmware support). Install instead
via the flake's own installer image:

```bash
# Build the Pi 5 installer image (bakes in an SSH key so it's reachable
# on first boot — edit custom-user-config or pass your key another way)
nix build .#nixosConfigurations.rpi5-installer.config.system.build.sdImage

# Physically flash it to the Pi's NVMe (drive connected to another
# machine) or to a bootstrap SD/USB card, boot the Pi from it.
```

Once booted from the installer:

```bash
ssh root@<installer-ip>
nixos-generate-config --show-hardware-config
# copy the output back into hosts/stage-plotiphar/hardware-configuration.nix,
# commit, then deploy the real config:
```

```bash
nixos-rebuild switch --flake github:TristonYoder/nix-config#stage-plotiphar \
  --target-host root@<pi-ip> --refresh
```

## Daily operations

```bash
# From the Pi itself (or via --target-host from elsewhere)
systemctl status kiosk-launcher kiosk-url-tracker kiosk-reset-button
journalctl -u kiosk-launcher -f
journalctl -u kiosk-url-tracker -f

# Force every instance back to the pairing URL without pressing the
# physical button:
sudo rm -rf /var/lib/kiosk/profile-*/Default /var/lib/kiosk/profile-*/current-url
sudo systemctl restart kiosk-launcher

```

## CEC display power control

Requires `v4l-utils` installed (see `hosts/stage-plotiphar/configuration.nix`) and the
user in the `video` group. Once the NixOS config is deployed, `cec-ctl` is on `$PATH`
and runs without `sudo`.

**TV prerequisites** (must be enabled once in the TV's menu):
- **SimpLink / HDMI-CEC**: On
- **Auto Power Sync** (or *Auto Power Link*): On

### Port 1 (`/dev/cec0`)

```bash
# Power ON — two-step: wake the TV then claim the active input
cec-ctl -s -d /dev/cec0 --playback --to 0 --image-view-on
cec-ctl -s -d /dev/cec0 --playback --active-source phys-addr=2.0.0.0

# Power OFF — broadcast standby opcode (0x36) to all devices on the bus
cec-ctl -s -d /dev/cec0 --playback --to 15 --custom-command cmd=0x36

# Power status check
cec-ctl -s -d /dev/cec0 --playback --to 0 --give-device-power-status

# Topology scan (shows all connected CEC devices and their addresses)
cec-ctl -s -d /dev/cec0 --playback -S
```

### Port 2 (`/dev/cec1`)

Same commands, substitute `/dev/cec1`. Physical address on Port 2 is `3.0.0.0`:

```bash
cec-ctl -s -d /dev/cec1 --playback --to 0 --image-view-on
cec-ctl -s -d /dev/cec1 --playback --active-source phys-addr=3.0.0.0

cec-ctl -s -d /dev/cec1 --playback --to 15 --custom-command cmd=0x36

cec-ctl -s -d /dev/cec1 --playback --to 0 --give-device-power-status
```

> [!NOTE]
> LG TVs (and some others) take 20–30 s to fully power on from standby. The power status
> will read `in transition from standby to on` during that window — this is normal.

## Troubleshooting

**A monitor shows nothing / wrong resolution:**
```bash
DISPLAY=:0 xrandr --query   # confirm the output is detected as connected
```
`kiosk-launcher.service` only starts an instance for outputs `xrandr`
reports connected at the moment it runs — replug and
`systemctl restart kiosk-launcher` if a monitor was connected after boot.

**Power button doesn't reset (or shuts the machine down instead):**
```bash
systemctl status kiosk-reset-button
cat /proc/bus/input/devices | grep -A5 pwr_button
```
Confirm `services.logind.settings.Login.HandlePowerKey` is `"ignore"` — if
logind is still handling the key, `kiosk-reset-button.service` isn't
reaching the device (check `journalctl -u kiosk-reset-button`).

**Fan:** the pwm-fan cooling device is firmware/device-tree level, not
Nix-configured here — verify with
`cat /sys/class/thermal/cooling_device*/type` after first boot.
