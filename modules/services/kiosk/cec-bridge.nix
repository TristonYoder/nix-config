# modules/services/kiosk/cec-bridge.nix
#
# Makes this kiosk a **Plotiphar Output Device**: it carries out the stage-plotifer
# web app's display-power requests on the HDMI-CEC bus, so a TV driven by this
# machine can be powered on/off and told to switch to its input from the app —
# including on a schedule.
#
# Why a separate outbound-polling service rather than something the kiosk browser does:
# a TV in standby drops the HDMI hotplug line, xrandr then reports no connected
# outputs, and kiosk-launcher exits (and retries). So at exactly the moment you
# most need display control — the TV is off and you want it on — there may be
# no browser running to act on. This is a plain systemd service with no
# dependency on X, the browser, or a connected output.
#
# It also polls outbound only: no inbound port, no firewall hole, and it works
# from a venue LAN behind NAT with no reachable address of its own.

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.kiosk.cecBridge;
  kioskCfg = config.modules.services.kiosk.browserKiosk;

  # Drives the CEC bus via v4l-utils' cec-ctl. libcec/cec-client is the more
  # commonly cited tool but needs a persistent daemon-ish session; cec-ctl is
  # one-shot per message, which suits a poll loop and keeps this service
  # stateless between cycles.
  agentScript = pkgs.writers.writePython3 "kiosk-cec-agent" {
    flakeIgnore = [ "E501" ];
  } ''
    import glob
    import json
    import os
    import re
    import subprocess
    import sys
    import time
    import urllib.error
    import urllib.request
    from datetime import datetime

    ORIGIN = "${cfg.originUrl}".rstrip("/")
    KIOSK_STATE_DIR = "${kioskCfg.stateDir}"
    STATE_DIR = "${cfg.stateDir}"
    POLL_INTERVAL = ${toString cfg.pollInterval}
    SCHEDULE_GRACE = ${toString cfg.scheduleGraceSeconds}
    CEC_CTL = "${pkgs.v4l-utils}/bin/cec-ctl"
    HOSTNAME = "${config.networking.hostName}"
    REQUEST_TIMEOUT = 20

    # How long to let a browser session handoff complete before concluding the
    # display was reset and starting over. Generous: it covers a launcher
    # restart plus a page load on a cold WiFi link.
    HANDOFF_WAIT_SECONDS = 120

    # Identifies this client honestly, and is load-bearing: plotiphar.com sits
    # behind Cloudflare, which 403s urllib's default "Python-urllib/x.y" agent.
    # Verified against the live origin -- without this every request fails
    # before it ever reaches the app.
    USER_AGENT = "PlotipharOutputDevice/1 (+https://plotiphar.com)"

    # The TV is logical address 0 by definition in CEC.
    TV_ADDR = "0"

    # An unconfigured adapter reports this physical address: the HDMI link is
    # down (display off at the mains, cable out, or a TV that drops hotplug in
    # standby). The vc4 driver derives the address from the sink's EDID and
    # won't allocate a logical address without one, so nothing can be
    # transmitted in this state -- including a wake-up. Verified on the Pi 5:
    # forcing --phys-addr does not override it.
    INVALID_PHYS_ADDR = "f.f.f.f"


    def log(message):
        print("kiosk-cec-agent: " + message, flush=True)


    def state_path(output, name):
        return os.path.join(STATE_DIR, output, name)


    def read_json(path):
        try:
            with open(path, "r") as handle:
                data = json.load(handle)
            return data if isinstance(data, dict) else None
        except (OSError, ValueError):
            return None


    def write_json(path, data):
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            # Credentials live in here, so never let them land world-readable
            # even briefly.
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as handle:
                json.dump(data, handle)
            return True
        except OSError as err:
            log("cannot write %s: %s" % (path, err))
            return False


    def forget(path):
        try:
            os.remove(path)
        except OSError:
            pass


    def run_cec(args, timeout=15):
        """Runs cec-ctl, returning combined output ("" on failure)."""
        try:
            result = subprocess.run(
                [CEC_CTL] + args,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
            return (result.stdout or "") + (result.stderr or "")
        except (subprocess.TimeoutExpired, OSError) as err:
            log("cec-ctl %s failed: %s" % (" ".join(args), err))
            return ""


    def normalize_connector(sysfs_name):
        """'card0-HDMI-A-1' -> 'HDMI-1', matching what xrandr (and therefore
        the kiosk profile directories) call the same output."""
        name = re.sub(r"^card\d+-", "", sysfs_name)
        return re.sub(r"^HDMI-A-(\d+)$", r"HDMI-\1", name)


    def drm_connector_names():
        """DRM connector id -> xrandr-style output name."""
        names = {}
        for path in glob.glob("/sys/class/drm/card*-*"):
            id_file = os.path.join(path, "connector_id")
            try:
                with open(id_file, "r") as handle:
                    connector_id = handle.read().strip()
            except OSError:
                continue
            names[connector_id] = normalize_connector(os.path.basename(path))
        return names


    def discover_adapters():
        """Maps each output name to its CEC device and physical address.

        Resolved through the DRM connector id both sides report rather than by
        assuming /dev/cec0 is HDMI-1 -- the numbering happens to line up on the
        Pi 5, but nothing guarantees it, and silently driving the wrong TV is a
        bad failure mode.
        """
        names = drm_connector_names()
        adapters = {}
        for device in sorted(glob.glob("/dev/cec*")):
            info = run_cec(["-d", device])
            connector = re.search(r"DRM Connector Info\s*:\s*card \d+, connector (\d+)", info)
            phys = re.search(r"Physical Address\s*:\s*([0-9a-fA-F.]+)", info)
            if not connector:
                continue
            output = names.get(connector.group(1))
            if not output:
                continue
            adapters[output] = {
                "device": device,
                "phys_addr": phys.group(1) if phys else INVALID_PHYS_ADDR,
            }
        return adapters


    # ── Pairing ──────────────────────────────────────────────────────────────
    #
    # One pairing code provisions everything for an output: this service's own
    # API credential, the screen it drives, and the browser's login. The device
    # owns the pairing (the browser never visits /pair itself) because only the
    # device can hold a credential -- a cookie in the kiosk profile is wiped by
    # the reset button, and there'd be nothing left to authenticate CEC calls.

    PAGE_STYLE = (
        "html,body{margin:0;height:100%;background:#07090f;color:#e5e7eb;"
        "display:flex;align-items:center;justify-content:center;"
        "font-family:system-ui,-apple-system,sans-serif;text-align:center}"
        ".code{font-size:14vw;font-weight:800;letter-spacing:.12em;color:#2dd4bf;"
        "margin:.3em 0;font-variant-numeric:tabular-nums}"
        ".hint{font-size:1.6vw;color:#94a3b8;max-width:40em;line-height:1.6}"
        ".name{font-size:1.4vw;color:#475569;margin-top:2em;letter-spacing:.08em}"
    )


    def write_pairing_page(output, code, device_label):
        """Renders the code fullscreen on the display itself.

        A local file:// page rather than a served one: at this point the device
        has no session, and the whole point is that it is showing a code to
        someone standing in front of it. It reloads itself on a timer so a
        regenerated code (they expire after 10 minutes) appears without anyone
        touching the machine, and so the approved state is picked up the moment
        write_handoff_page replaces this file.
        """
        html = (
            "<!doctype html><html><head><meta charset='utf-8'>"
            "<meta http-equiv='refresh' content='5'>"
            "<style>%s</style></head><body><div>"
            "<div class='hint'>Pair this display in Plotiphar &mdash; "
            "Settings &rarr; Screens &rarr; Pair a Display</div>"
            "<div class='code'>%s</div>"
            "<div class='name'>%s</div>"
            "</div></body></html>"
        ) % (PAGE_STYLE, code, device_label)
        write_page(output, html)


    def write_handoff_page(output, handoff_url):
        """Sends the browser through its one-time session handoff.

        A meta-refresh (top-level navigation), never a fetch: the handoff token
        is single use, so a prefetch would burn it and leave the real
        navigation with nothing to redeem. This is also why the kiosk launcher
        opens file:// URLs directly instead of via its usual connectivity
        pre-check page.
        """
        html = (
            "<!doctype html><html><head><meta charset='utf-8'>"
            "<meta http-equiv='refresh' content='0; url=%s'>"
            "<style>%s</style></head><body>"
            "<div class='hint'>Paired &mdash; opening your screen&hellip;</div>"
            "</body></html>"
        ) % (ORIGIN + handoff_url, PAGE_STYLE)
        # Marks the handoff window open before the page goes live, so a crash
        # between the two can only make resolve_identity re-pair (safe) rather
        # than wait forever on a handoff that never started.
        write_json(state_path(output, "handoff.json"), {"at": time.time()})
        write_page(output, html)


    def write_page(output, html):
        path = os.path.join(STATE_DIR, "pair-%s.html" % output)
        try:
            os.makedirs(STATE_DIR, exist_ok=True)
            with open(path, "w") as handle:
                handle.write(html)
        except OSError as err:
            log("cannot write pairing page for %s: %s" % (output, err))
            return
        point_browser_at(output, "file://" + path)


    def point_browser_at(output, url):
        """Sets the URL the kiosk launcher opens for this output.

        Writes the same current-url file kiosk-url-tracker maintains, so once
        the browser lands on /screens/<id> the tracker takes over and persists
        the real URL -- the pairing page is never written back over it.
        """
        path = os.path.join(KIOSK_STATE_DIR, "profile-%s" % output, "current-url")
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "r") as handle:
                if handle.read().strip() == url:
                    return
        except OSError:
            pass
        try:
            with open(path, "w") as handle:
                handle.write(url)
        except OSError as err:
            log("cannot point %s at %s: %s" % (output, url, err))
            return
        subprocess.run(
            ["systemctl", "restart", "kiosk-launcher.service"], check=False
        )


    def has_kiosk_profile(output):
        """True if the browser kiosk brought this output up (i.e. it has a
        display attached)."""
        return os.path.isdir(os.path.join(KIOSK_STATE_DIR, "profile-%s" % output))


    def browser_has_screen(output):
        """True once the browser is sitting on a real screen URL."""
        path = os.path.join(KIOSK_STATE_DIR, "profile-%s" % output, "current-url")
        try:
            with open(path, "r") as handle:
                return "/screens/" in handle.read()
        except OSError:
            return False


    def start_pairing(output):
        label = "%s %s" % (HOSTNAME, output)
        try:
            result = api_post(
                "/api/auth/device/start",
                {"client": "output-device", "name": label},
                None,
            )
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError) as err:
            log("%s: cannot start pairing: %s" % (output, err))
            return None
        pairing = {
            "deviceToken": result.get("deviceToken"),
            "code": result.get("code"),
            "expiresAt": result.get("expiresAt"),
        }
        if not pairing["deviceToken"] or not pairing["code"]:
            log("%s: pairing start returned no token" % output)
            return None
        write_json(state_path(output, "pairing.json"), pairing)
        log("%s: pairing code %s" % (output, pairing["code"]))
        write_pairing_page(output, pairing["code"], label)
        return pairing


    def poll_pairing(output, pairing):
        """Checks whether someone has approved this device's code yet.

        Returns the stored credential once approved, else None.
        """
        try:
            result = api_post(
                "/api/auth/device/status",
                {"deviceToken": pairing["deviceToken"]},
                None,
            )
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError) as err:
            log("%s: cannot poll pairing: %s" % (output, err))
            return None

        status = result.get("status")
        if status == "pending":
            return None
        if status != "approved":
            # Expired (or already claimed) -- drop it and take a fresh code on
            # the next cycle rather than leaving a dead code on the screen.
            log("%s: pairing code expired, requesting a new one" % output)
            forget(state_path(output, "pairing.json"))
            return None

        credential = {
            "sessionToken": result.get("sessionToken"),
            "screenId": result.get("screenId"),
        }
        if not credential["sessionToken"] or not credential["screenId"]:
            log("%s: approval returned no credential or screen" % output)
            forget(state_path(output, "pairing.json"))
            return None

        if not write_json(state_path(output, "credential.json"), credential):
            return None
        forget(state_path(output, "pairing.json"))
        log("%s: paired to screen %s" % (output, credential["screenId"]))

        handoff = result.get("browserHandoffUrl")
        if handoff:
            write_handoff_page(output, handoff)
        return credential


    def clear_pairing_artifacts(output):
        """Drops the on-screen page and the handoff marker.

        Called once the browser is actually on its screen, so that "a pairing
        page still exists" always means "the handoff hasn't finished" -- see
        resolve_identity, which depends on that being unambiguous.
        """
        forget(state_path(output, "handoff.json"))
        forget(os.path.join(STATE_DIR, "pair-%s.html" % output))


    def handoff_in_flight(output):
        marker = read_json(state_path(output, "handoff.json"))
        if not marker:
            return False
        try:
            return (time.time() - float(marker.get("at", 0))) < HANDOFF_WAIT_SECONDS
        except (TypeError, ValueError):
            return False


    def resolve_identity(output):
        """Gets this output's credential, driving the pairing flow if needed.

        Also implements the reset button. That button wipes the browser profile
        -- cookies and current-url -- which is an explicit "re-pair this
        display" instruction, so a credential with no browser screen behind it
        is discarded rather than kept alive against a display nobody can see.

        The only case where a missing screen ISN'T a reset is the brief window
        between writing the handoff page and the browser landing on its screen.
        That window is tracked with an explicit, expiring marker rather than
        inferred from the pairing page still being on disk: that page outlives
        a successful handoff unless something deletes it, so inferring from it
        would make a reset look like a permanent handoff-in-progress and leave
        the display stuck on the holding page forever.
        """
        credential = read_json(state_path(output, "credential.json"))
        if credential and credential.get("sessionToken"):
            if browser_has_screen(output):
                clear_pairing_artifacts(output)
                return credential
            if handoff_in_flight(output):
                return credential
            log("%s: browser was reset, re-pairing" % output)
            forget(state_path(output, "credential.json"))
            clear_pairing_artifacts(output)
            credential = None

        pairing = read_json(state_path(output, "pairing.json"))
        if not pairing:
            pairing = start_pairing(output)
            if not pairing:
                return None
            return None
        return poll_pairing(output, pairing)


    def query_power_state(device):
        output = run_cec(["-d", device, "--skip-info", "--to", TV_ADDR,
                          "--give-device-power-status"])
        match = re.search(r"pwr-state:\s*([a-z-]+)", output)
        if not match:
            return "unknown"
        state = match.group(1)
        if state == "on":
            return "on"
        if state == "standby":
            return "standby"
        # Mid-transition: report where the display is heading, which is what
        # someone watching the dashboard actually wants to know.
        if state == "in-transition-standby-to-on":
            return "on"
        if state == "in-transition-on-to-standby":
            return "standby"
        return "unknown"


    def send_action(device, phys_addr, action):
        """Executes one CEC action. Returns None on success, else an error string."""
        if phys_addr == INVALID_PHYS_ADDR:
            return ("HDMI link is down (no physical address) -- the display "
                    "cannot be reached over CEC until it is powered on at the set")

        if action == "standby":
            run_cec(["-d", device, "--skip-info", "--to", TV_ADDR, "--standby"])
            return None

        if action == "active-source":
            run_cec(["-d", device, "--skip-info",
                     "--active-source", "phys-addr=" + phys_addr])
            return None

        if action == "on":
            # One Touch Play: wake the panel, then claim its input. Sending
            # only IMAGE_VIEW_ON commonly powers a TV on but leaves it on
            # whatever input it was last showing.
            run_cec(["-d", device, "--skip-info", "--to", TV_ADDR, "--image-view-on"])
            time.sleep(1)
            run_cec(["-d", device, "--skip-info",
                     "--active-source", "phys-addr=" + phys_addr])
            return None

        return "unknown action: " + str(action)


    def api_post(path, payload, token):
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(ORIGIN + path, data=body, method="POST")
        request.add_header("Content-Type", "application/json")
        request.add_header("User-Agent", USER_AGENT)
        if token:
            # The device session from pairing, presented as a Bearer token --
            # this service has nowhere to keep a cookie. Every call also
            # refreshes the session's sliding expiry, which is what keeps a
            # paired display paired without anyone re-entering a code.
            request.add_header("Authorization", "Bearer " + token)
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            return json.loads(response.read().decode("utf-8"))


    def report(screen_id, token, power_state, adapter_label, error, ack_command_id=None):
        payload = {
            "powerState": power_state,
            "timezone": current_timezone(),
            "adapter": adapter_label,
            "error": error,
        }
        if ack_command_id:
            payload["ackCommandId"] = ack_command_id
        return api_post("/api/screens/%s/cec/report" % screen_id, payload, token)


    def current_timezone():
        """Prefers the IANA zone name over the abbreviation.

        The dashboard labels the schedule with whatever this returns, and
        'America/Indiana/Indianapolis' is unambiguous where 'EST' is not (and
        would also flip to 'EDT' half the year for the same schedule). Python
        has no stdlib accessor for the configured zone name, but on NixOS
        /etc/localtime is a symlink into the tzdata store path.
        """
        try:
            target = os.path.realpath("/etc/localtime")
            match = re.search(r"/zoneinfo/(.+)$", target)
            if match:
                return match.group(1)
        except OSError:
            pass
        try:
            return datetime.now().astimezone().tzname() or ""
        except (OSError, ValueError):
            return ""


    def schedule_state_path(screen_id):
        return os.path.join(STATE_DIR, "schedule-%s.json" % screen_id)


    def load_schedule_state(screen_id):
        try:
            with open(schedule_state_path(screen_id), "r") as handle:
                data = json.load(handle)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}


    def save_schedule_state(screen_id, state):
        try:
            os.makedirs(STATE_DIR, exist_ok=True)
            with open(schedule_state_path(screen_id), "w") as handle:
                json.dump(state, handle)
        except OSError as err:
            log("cannot persist schedule state for %s: %s" % (screen_id, err))


    def due_schedule_entries(schedule, fired, now):
        """Entries that should fire right now.

        Evaluated against the host's own local time, deliberately: a venue's
        displays follow venue-local wall-clock time regardless of where the app
        is hosted or which timezone whoever edited the schedule is in.

        Two guards keep this from misfiring:
          - a grace window, so an entry whose time passed long ago (this service
            was down, or the machine was off) does not fire late -- powering a display on
            hours after its 8am rule is worse than skipping it;
          - a per-day fired marker, so an entry fires at most once per day even
            though the loop revisits it every cycle.
        """
        due = []
        today = now.strftime("%Y-%m-%d")
        for entry in schedule:
            entry_id = entry.get("id")
            action = entry.get("action")
            entry_time = entry.get("time", "")
            days = entry.get("days") or []
            if not entry_id or not action:
                continue
            # Python's weekday() is Mon=0; the app's schedule uses Sun=0.
            if ((now.weekday() + 1) % 7) not in days:
                continue
            match = re.match(r"^([01]\d|2[0-3]):([0-5]\d)$", entry_time)
            if not match:
                continue
            if fired.get(entry_id) == today:
                continue
            scheduled = now.replace(
                hour=int(match.group(1)),
                minute=int(match.group(2)),
                second=0,
                microsecond=0,
            )
            elapsed = (now - scheduled).total_seconds()
            if 0 <= elapsed <= SCHEDULE_GRACE:
                due.append((entry_id, action, today))
        return due


    def handle_screen(output, screen_id, adapter, token):
        device = adapter["device"]
        # Re-read the physical address each cycle: it changes when the display
        # is powered on or off underneath us.
        info = run_cec(["-d", device])
        phys_match = re.search(r"Physical Address\s*:\s*([0-9a-fA-F.]+)", info)
        phys_addr = phys_match.group(1) if phys_match else INVALID_PHYS_ADDR
        adapter_label = "%s -> %s" % (output, device)

        link_down = phys_addr == INVALID_PHYS_ADDR
        power_state = "unknown" if link_down else query_power_state(device)
        error = None
        if link_down:
            error = ("HDMI link is down -- the display is unreachable over CEC "
                     "(powered off at the set, or cable disconnected)")

        state = report(screen_id, token, power_state, adapter_label, error)
        if not state.get("enabled"):
            return

        actions = []
        command = state.get("command")
        if command and command.get("action"):
            actions.append((command["action"], command.get("id"), None))

        schedule = state.get("schedule") or []
        if schedule:
            fired = load_schedule_state(screen_id)
            for entry_id, action, today in due_schedule_entries(schedule, fired, datetime.now()):
                actions.append((action, None, (entry_id, today)))

        if not actions:
            return

        for action, command_id, schedule_mark in actions:
            log("%s: running %s" % (screen_id, action))
            action_error = send_action(device, phys_addr, action)
            if action_error:
                log("%s: %s failed: %s" % (screen_id, action, action_error))

            if schedule_mark:
                # Marked as fired even when the send failed: retrying every
                # cycle for the rest of the grace window would just spam a
                # display that is unreachable anyway.
                entry_id, today = schedule_mark
                fired = load_schedule_state(screen_id)
                fired[entry_id] = today
                save_schedule_state(screen_id, fired)

            if command_id:
                # Re-read power state so the dashboard reflects the result of
                # the command immediately rather than one poll interval later.
                time.sleep(2)
                refreshed_info = run_cec(["-d", device])
                refreshed_match = re.search(r"Physical Address\s*:\s*([0-9a-fA-F.]+)", refreshed_info)
                refreshed_phys = refreshed_match.group(1) if refreshed_match else INVALID_PHYS_ADDR
                new_state = "unknown" if refreshed_phys == INVALID_PHYS_ADDR else query_power_state(device)
                report(screen_id, token, new_state, adapter_label,
                       action_error, ack_command_id=command_id)


    def main():
        log("polling %s every %ds" % (ORIGIN, POLL_INTERVAL))
        while True:
            try:
                # Re-discovered every cycle rather than cached at startup: a
                # display can be plugged into the second port, or swapped, long
                # after this service came up.
                adapters = discover_adapters()
                for output in sorted(adapters):
                    try:
                        if not has_kiosk_profile(output):
                            # Nothing is driving this port. An unconnected
                            # output and a sleeping TV both report f.f.f.f, so
                            # the CEC adapter can't tell them apart -- but the
                            # launcher only creates a profile for an output
                            # xrandr saw connected, which can. Without this,
                            # an empty second HDMI port would pair itself and
                            # conjure a screen nobody asked for.
                            continue
                        credential = resolve_identity(output)
                        if not credential:
                            continue
                        handle_screen(
                            output,
                            credential["screenId"],
                            adapters[output],
                            credential["sessionToken"],
                        )
                    except urllib.error.HTTPError as err:
                        if err.code in (401, 403):
                            # The session was revoked (member removed, session
                            # deleted, org changed). Nothing this service can
                            # do but ask to be paired again.
                            log("%s: credential rejected (%s), re-pairing" % (output, err.code))
                            forget(state_path(output, "credential.json"))
                        else:
                            log("%s: API returned %s" % (output, err.code))
                    except (urllib.error.URLError, TimeoutError, ValueError) as err:
                        log("%s: API unreachable: %s" % (output, err))
            except Exception as err:  # noqa: BLE001 - the loop must never die
                log("unexpected error: %s" % err)
            time.sleep(POLL_INTERVAL)


    if __name__ == "__main__":
        sys.exit(main())
  '';
in
{
  options.modules.services.kiosk.cecBridge = {
    enable = mkEnableOption "Plotiphar Output Device — carries out the stage-plotifer app's display power/input requests over HDMI-CEC";

    originUrl = mkOption {
      type = types.str;
      default = kioskCfg.originUrl;
      description = ''
        Base origin of the stage-plotifer app. Defaults to whatever the browser
        kiosk points at, so this service and the displays can't drift apart.
      '';
    };

    pollInterval = mkOption {
      type = types.ints.positive;
      default = 15;
      description = ''
        Seconds between heartbeats. Also bounds how long a queued command waits
        before it runs, so raising this makes the dashboard buttons feel slower.
      '';
    };

    scheduleGraceSeconds = mkOption {
      type = types.ints.positive;
      default = 300;
      description = ''
        How late a scheduled entry may still fire. Covers a brief restart of this
        service
        or network blip without resurrecting a rule whose time passed hours ago
        — a display powering on long after its scheduled time is worse than one
        that stays off.
      '';
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/kiosk-cec";
      description = ''
        Directory holding, per output, the pairing in progress, the device
        credential issued when it was approved, and which schedule entries have
        already fired today. Contains a live credential, so it is created 0700
        and the credential file itself 0600 — nothing here should be readable
        by anyone but this service's user.
      '';
    };

    user = mkOption {
      type = types.str;
      default = kioskCfg.user;
      description = ''
        User this runs as. Must be in the `video` group to open /dev/cec*.
        Defaults to the kiosk user, which browser-kiosk.nix already puts there.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = kioskCfg.enable;
        message = ''
          modules.services.kiosk.cecBridge requires modules.services.kiosk.browserKiosk:
          it discovers which screen each HDMI output is paired to by reading the
          browser kiosk's per-output current-url files.
        '';
      }
    ];

    # cec-ctl for this service, plus cec-client so an admin debugging a CEC issue
    # on the box has the tool most CEC documentation refers to.
    environment.systemPackages = with pkgs; [ v4l-utils libcec ];

    # This service owns pairing for every output, so the browser must not also
    # go mint its own code — see the option's description.
    modules.services.kiosk.browserKiosk.pairingHandledExternally = true;

    # Restarting kiosk-launcher is how a new URL (the pairing page, then the
    # session handoff) actually reaches the screen. Scoped to that one unit and
    # that one user rather than granting broader systemd rights.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "kiosk-launcher.service" &&
            subject.user == "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';

    # 0700, not 0750: this holds the device session token.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 ${cfg.user} ${config.users.users.${cfg.user}.group} -"
    ];

    systemd.services.kiosk-cec-agent = {
      description = "Plotiphar Output Device — display power/input control over HDMI-CEC";
      # Wants (not Requires) network-online: the poll loop tolerates an
      # unreachable API and retries, so a slow-to-associate WiFi link at boot
      # shouldn't fail the unit.
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${agentScript}";
        # Restarts kiosk-launcher after re-pointing an output at a new URL.
        Environment = [ "PATH=${makeBinPath [ pkgs.systemd ]}" ];
        Restart = "always";
        RestartSec = "10s";
        # Opens /dev/cec* (root:video 0660).
        SupplementaryGroups = [ "video" ];

        # Nothing here needs write access outside its own state directory.
        StateDirectory = baseNameOf cfg.stateDir;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        # Writes its own state, plus each output's current-url — that file is
        # how it hands the browser the pairing page and then the handoff URL.
        ReadWritePaths = [ cfg.stateDir kioskCfg.stateDir ];
      };
    };
  };
}
