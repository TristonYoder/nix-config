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
- **Display power**: optionally acts as a Plotiphar Output Device, letting the
  app power the TV and switch its input — see
  [Display power control](#display-power-control-plotiphar-output-device) below

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

## Display power control (Plotiphar Output Device)

`modules.services.kiosk.cecBridge` (see
`modules/services/kiosk/cec-bridge.nix`) makes this Pi a **Plotiphar Output
Device**: the app can power this venue's TV on/standby and switch it to the
Pi's HDMI input — from Settings → Screens in the app, or on a per-screen
schedule.

As an Output Device it runs `kiosk-cec-agent.service`, which polls
`POST <origin>/api/screens/<id>/cec/report` every 15s. Each heartbeat reports
what it sees on the HDMI-CEC bus and returns any pending command plus the
screen's schedule, so one request per cycle covers both directions. It is
outbound-only: no inbound port, and it works from the venue LAN with no
reachable address.

It figures out what to drive with no extra configuration:

- **Which screen** — from the pairing below; the screen id is issued to this
  host when its code is approved, and stored per output.
- **Which adapter** — matches each `/dev/cec*` to an `xrandr` output via the
  DRM connector id both report, rather than assuming `/dev/cec0` is `HDMI-1`.
  (On this Pi they do line up — `HDMI-1` → connector 35 → `/dev/cec0` — but
  nothing guarantees it, and driving the wrong TV is a bad failure mode.)

Schedules are evaluated **on this Output Device, in its own local time**
(`America/Indiana/Indianapolis`), not on the server — venue displays should
follow venue wall-clock time regardless of where the app runs. An entry whose
time passed more than `scheduleGraceSeconds` (default 300) ago is skipped
rather than fired late.

### Pairing — one code provisions everything

There is no secret to deploy. On first boot the display shows a pairing code;
entering it in the app (Settings → Screens → Pair a Display) issues this host
its own credential, creates or binds its screen, and signs the kiosk browser
in — all from that one code.

The Output Device owns the pairing rather than the browser, which matters for
two reasons. Only the device can hold a credential: a cookie in the Chromium
profile is wiped by the reset button, and there'd be nothing left to
authenticate CEC calls with. And if the browser minted its own code first, you
could approve a code that signed the browser in while leaving the device
unpaired — so `browserKiosk.pairingHandledExternally` suppresses the browser's
own `/pair` fallback whenever this module is on.

What happens on the wire:

1. The agent calls `/api/auth/device/start` as `client: "output-device"`,
   naming itself `<hostname> <output>`, and gets a code plus a device token
   (in the body — it has no cookie jar).
2. It writes a local page showing that code and points the output's
   `current-url` at it. The page reloads itself, so a regenerated code (they
   expire after 10 minutes) appears with nobody touching the machine.
3. Someone approves the code. Leaving the screen selector on *Automatic*
   creates a screen named after the device, with display power already on.
4. The agent's next `/api/auth/device/status` poll returns its **session
   token** (sent as `Authorization: Bearer` from then on), its **screen id**,
   and a **single-use browser handoff URL**.
5. It rewrites the local page into a top-level redirect to that handoff URL.
   The browser follows it once, picks up its own session cookie, and lands on
   `/screens/<id>` — after which `kiosk-url-tracker` persists the real URL as
   it always has.

The session has a 90-day sliding expiry that every heartbeat refreshes, so a
paired display stays paired indefinitely. Pressing the reset button wipes the
browser profile, which the agent reads as "re-pair this display": it discards
its credential and shows a fresh code.

```bash
# What this output currently thinks it is
sudo ls /var/lib/kiosk-cec/                        # pair-<output>.html is what's on screen
sudo cat /var/lib/kiosk-cec/HDMI-1/credential.json  # 0600 — holds a live session token

# Force a re-pair of one output
sudo rm -rf /var/lib/kiosk-cec/HDMI-1 /var/lib/kiosk/profile-HDMI-1/current-url
sudo systemctl restart kiosk-cec-agent
```

### The standby limitation

**A TV that cuts the HDMI link when it powers off cannot be woken over CEC
from this Output Device.** The `vc4` driver takes its CEC physical address
from the sink's EDID; with the link down the address reads `f.f.f.f`, no logical
address is allocated, and nothing can be transmitted. Forcing
`cec-ctl --phys-addr` does not override this (confirmed on this Pi).

Many TVs — including the LG panel here — keep CEC alive in standby precisely
so One Touch Play works, in which case wake-up is fine. If yours doesn't, the
Output Device reports the display as unreachable with that reason rather
than silently failing, and standby/input switching still work whenever the set is on. Check
which behavior you have:

```bash
# With the TV in standby:
cec-ctl -d /dev/cec0 | grep "Physical Address"
# 2.0.0.0 → CEC stays alive in standby, wake-up will work
# f.f.f.f → the link drops, this Output Device cannot wake it
```

### Operations

```bash
systemctl status kiosk-cec-agent
journalctl -u kiosk-cec-agent -f

# What the bus looks like right now
cec-ctl -d /dev/cec0 -S                              # topology + TV vendor/OSD name
cec-ctl -d /dev/cec0 --to 0 --give-device-power-status

# Drive it by hand (the same messages the Output Device sends)
cec-ctl -d /dev/cec0 --to 0 --image-view-on           # wake
cec-ctl -d /dev/cec0 --active-source phys-addr=2.0.0.0  # claim this input
cec-ctl -d /dev/cec0 --to 0 --standby                 # sleep
```

`/dev/cec0` is HDMI-1 (`hdmi0`, the port nearer the USB-C jack) and `/dev/cec1`
is HDMI-2. With nothing plugged into the second port, `cec-ctl -d /dev/cec1`
reporting `f.f.f.f` is expected, not a fault.

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
