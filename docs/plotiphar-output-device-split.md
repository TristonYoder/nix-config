# Plotiphar Output Device — standalone repo

Status: design, not yet built. Written 2026-08-14.

Extracts the signage-kiosk work out of this homelab repo into a repo that ships
a **product image** for devices deployed at customer venues, with its own CI,
release process, and update mechanism.

---

## Why this needs to move

The extraction itself is small. The reason to do it is that the current design
is *host-shaped* and needs to be *fleet-shaped*, and three of the four problems
below will bite regardless of which repo the code lives in.

**1. One `nixosConfiguration` per machine.** `flake.nix` carries an explicit
`stage-plotiphar = nixpkgs.lib.nixosSystem { … }` entry, and
`modules/system/auto-update.nix` rebuilds from
`github:<owner>/<repo>#$(hostname)` — keyed on hostname. Every new device today
means a new hostname, a new flake entry, a generated
`hardware-configuration.nix`, and a commit. Correct for seven homelab hosts.
Unworkable for a fleet.

**2. Secrets are O(N), in a public repo.** `secrets/secrets.nix` scopes device
secrets with `stagePlotipharKeys = [ stage-plotiphar ] ++ adminKeys` — each
device is its own age recipient, so every new unit means a new host key and
re-encrypting every device secret for it. This repo is public, so customer WiFi
PSKs live here encrypted. Encrypted is not the same as appropriate once it is
fifty churches' credentials.

**3. Deploy is push-over-tailnet.** `.github/workflows/deploy-nixos-config.yml`
SSHes to `<host>.vpn.theyoder.family`, and `profiles/kiosk.nix` sets
`modules.services.infrastructure.tailscale.enable = lib.mkDefault true` — so
every customer device would join the operator's *personal* tailnet. Venue
devices sit behind NAT and need to pull, not be pushed to.

**4. Homelab assumptions leak in.** `common/system.nix` sets
`networking.domain = "theyoder.family"`; `profiles/kiosk.nix` enables
`vscode-server` and creates the operator's user account. None of that belongs
on a customer's device.

**What changed recently, and why this is now viable:** the Output Device
pairing flow removed the main per-device blocker. A device no longer needs an
API key or screen id baked into its config — it self-identifies with a code at
first boot and receives its own credential, its screen binding, and its
browser session from that one code. The only per-device secret left is the
venue's WiFi, which this design also removes (see *First boot*).

---

## Scope

**Moves to the new repo**

| Path | Notes |
|---|---|
| `modules/services/kiosk/browser-kiosk.nix` | per-output Chromium, URL persistence, reset button |
| `modules/services/kiosk/cec-bridge.nix` | the Output Device agent: pairing, CEC ladders, schedule |
| `profiles/kiosk.nix` | rewritten lean — see below |
| `hosts/stage-plotiphar/*` | becomes the generic device config, not a host |
| `hosts/installer/rpi5.nix` | installer image |
| `secrets/stage-plotiphar-wifi-psk.age` | **deleted, not moved** — obsoleted by first-boot setup |

**Stays here.** `common/*`, `modules/system/*`, `modules/hardware/*`,
`modules/services/{infrastructure,providers,…}`, everything else.

**Do not consume `nix-config` as a flake input.** It is tempting — it would
avoid rewriting ~450 lines of base config — but it couples the product's
release cadence to the homelab repo and drags the homelab's assumptions
(domain, operator user, vscode-server, tailnet) into customer devices. The base
the new repo needs is small and mostly *different*, not shared. Write it lean.

---

## Architecture

### One image, not many hosts

The new repo exposes **one** `nixosConfiguration` and an image artifact built
from it. No `hosts/` directory. Adding a device to the fleet involves flashing
an image and powering it on — no commit, no flake entry, no key.

Everything that differs per device becomes **runtime state on the device**, not
Nix configuration:

| Per-device thing | Where it lives now | Where it goes |
|---|---|---|
| App credential, screen binding | — (already solved) | issued by pairing, `/var/lib/kiosk-cec/<output>/credential.json` |
| WiFi credentials | agenix, per host, in this repo | NetworkManager state, entered at first boot |
| Hostname | `hosts/<name>/configuration.nix` | derived from the Pi's serial at first boot |
| `hardware-configuration.nix` | generated per machine | declarative + `disko`; identical hardware, identical config |

### First boot: the network state machine

The device is useless until it is on the venue's network, and the venue's
network cannot be known at build time. The device provisions itself:

```
        ┌──────────────┐
        │ unconfigured │
        └──────┬───────┘
               │ no saved connection
               ▼
        ┌──────────────┐   installer joins AP, submits venue SSID + PSK
        │  setup AP    │──────────────────────────┐
        └──────┬───────┘                          │
               │                                  ▼
               │                          ┌────────────────┐
               │      connect fails       │   connecting   │
               │◄─────────────────────────┴───────┬────────┘
               │                                  │ online
               │                                  ▼
               │                          ┌────────────────┐
               │                          │    pairing     │  ← shows pairing code
               │                          └───────┬────────┘
               │                                  │ approved
               │   saved connection down          ▼
               │   for > graceDuration    ┌────────────────┐
               └──────────────────────────┤    running     │
                                          └────────────────┘
```

**Setup AP.** With no saved connection, the device brings up its own access
point:

- SSID `PlotipharDisplay_<shortUUID>` — short, stable per device, distinguishes
  units when several are being commissioned in the same room.
- A randomly generated password, minimum length enforced. Generated once and
  persisted, so it survives a reboot mid-commissioning.
- The **display shows a QR code** encoding the WiFi credentials
  (`WIFI:S:<ssid>;T:WPA;P:<password>;;`, the standard phone-camera format),
  alongside the SSID and password as text for anyone whose camera won't
  cooperate.
- Joining the AP serves a small local page to pick the venue SSID and enter its
  PSK. The device writes a NetworkManager profile and drops the AP.

**Re-entry.** If a saved connection fails for longer than a grace duration, the
device returns to the setup AP. This is the recovery path for "the church
changed their WiFi password", which otherwise means a site visit.

**Reuse what exists.** `cec-bridge.nix` already owns a fullscreen local page on
the display — it writes `pair-<output>.html` and points `current-url` at it,
and the kiosk launcher opens `file://` targets directly. The setup screen is
another state of that same mechanism, not new machinery. The grace-window and
marker-file patterns in `resolve_identity` are the model to follow.

**Security note.** The setup AP is an open door while it is up: anyone in range
who can see the screen can join. That is acceptable because it is only up
before the device is commissioned and it grants nothing but the ability to
submit a network. It must *not* come up while the device is running normally —
only from `unconfigured`, or after a sustained connection failure.

### Updates: channels with staged promotion

Devices track a **channel**, not a branch, and pull on a timer with jitter (a
fleet waking simultaneously is its own denial of service).

```
main ──build──> artifact ──publish──> beta ──promote──> stable
                                       │                  │
                                  test venue          everyone else
```

- `stable` is what venues run. `beta` is what your own test device runs.
- Promotion is an explicit action — retagging a proven build, never a rebuild.
  The bits that reach stable are the exact bits that were proven on beta.
- Roll back by re-pointing the channel at the previous build. NixOS generations
  mean the device can also roll itself back locally if activation fails.
- **Never update during an event.** The screen knows its own schedule and
  whether an event is currently assigned; the updater must defer while content
  is live. A display rebooting mid-service is the worst possible failure.

### Remote support: on-demand, not always-on

**Decision: start with on-demand access over the existing command channel.**

The device already polls `POST /api/screens/<id>/cec/report` every 15s and
executes commands from a queue. Support access becomes another command type:
an operator requests a session in the dashboard, the device picks it up on its
next heartbeat, opens an outbound tunnel for a bounded window, and tears it
down when the window closes.

Why this over an always-on mesh:

- No permanent tunnel into a customer's network — a much easier thing to put in
  front of a church's IT volunteer, and a smaller surface.
- Every session is a row in the command table, attributable to a user. Audit
  for free.
- Reuses machinery that is already built and proven, at roughly zero cost.

The honest counter-argument: a device broken badly enough that it cannot poll
also cannot be reached this way. Weigh that against the observed failure modes
— the launcher crash-loop, the unconfigured CEC adapter, the stale
service-worker bundle — all of which had a healthy network and a live agent. A
device that cannot reach the app usually cannot reach a lighthouse either.

**If always-on becomes necessary, use Nebula.** Certificate-based, MIT, built
by Slack for their own infrastructure, and it scales to tens of thousands of
hosts because trust lives in certificates rather than a control plane that has
to be online — lighthouses are only rendezvous points. The usual objection is
running a CA and an enrollment process, and **that problem is already solved
here**: pairing is the enrollment point. One code could issue the app
credential *and* a Nebula certificate.

Design device identity so that stays possible. Rejected alternatives:
headscale (makes a homelab-grade control plane a hard dependency for customer
hardware), hosted Tailscale (per-device pricing across many venues).

### CI

Nothing like this repo's dry-run-and-SSH matrix.

1. **PR** — evaluate the config, build the image, boot it in a VM and assert it
   reaches the setup-AP state. A build that cannot boot is the failure mode
   that matters, and it is cheap to catch.
2. **Merge to main** — build the aarch64 image, sign it, push to a binary
   cache, publish a release artifact, point `beta` at it.
3. **Promote** — a manual workflow that re-points `stable` at an existing
   build. No rebuild.

aarch64 builds need real arm64 capacity: GitHub-hosted arm64 runners, or the
existing self-hosted runner and `linux-builder`. Note that this repo's current
`test-configurations` matrix does **not** include `stage-plotiphar` — the host
all of this targets has never been built in CI. Do not carry that gap forward.

---

## Repo layout

```
plotiphar-device/
├── flake.nix                  # one nixosConfiguration + image outputs
├── modules/
│   ├── kiosk/                 # browser-kiosk.nix, cec-bridge.nix
│   ├── provisioning/          # setup AP, network state machine, hostname
│   └── update/                # channel tracking, event-aware deferral
├── profile.nix                # the lean device base (replaces profiles/kiosk.nix)
├── image/                     # disko layout, installer, sdImage
├── .github/workflows/         # build, release, promote
└── docs/
```

---

## Milestones

1. **Repo skeleton + generic image.** One config, no per-host anything, builds
   an aarch64 image in CI. Existing kiosk + CEC modules carried over intact.
2. **First-boot provisioning.** Setup AP, QR screen, network state machine,
   serial-derived hostname. This is what makes the image generic and deletes
   the last per-device secret.
3. **Channels + release pipeline.** Build/sign/publish/promote, event-aware
   deferral, jittered pull.
4. **On-demand remote support** over the command channel.
5. **Retire from `nix-config`.** Remove the kiosk modules, `hosts/stage-plotiphar*`,
   the WiFi secret and its `secrets.nix` entry; confirm the remaining hosts
   still evaluate.

1 and 2 are the ones that unblock scale. 5 lands last, after a real device has
run the new image.

---

## Decided since writing

- **Hardware: CM5 only, for now.** One board means one `hardware-configuration`
  and no runtime branching. If a bare Pi 5 is added later the split is on
  filesystems and boot, not on anything above — keep board-specific settings in
  `image/hardware.nix` rather than letting them leak into the device profile,
  so adding a second board stays a new file rather than a refactor.

## Open questions

- **Image target.** The current Pi boots from onboard NVMe, which the installer
  image writes. Does the fleet flash NVMe directly at provisioning time, or ship
  from an SD/USB installer?
- **Channel assignment.** How does a device know it is on `beta` — baked into
  the image, or set from the app once paired? The latter is better (one image,
  reassignable) and fits the existing command channel.
- **Repo visibility.** Public makes the image reproducible and auditable, which
  suits an open-core product; it also publishes your fleet's exact attack
  surface. No per-device secrets remain either way, which makes public viable
  in a way it is not today.
