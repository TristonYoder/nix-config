# modules/services/kiosk/browser-kiosk.nix
#
# One fullscreen Chromium instance per connected HDMI/DisplayPort output,
# each instance's assigned screen URL persisted to disk so it survives a
# reboot without re-pairing, plus a handler for the onboard power button
# that wipes all instances back to the pairing URL instead of shutting
# the machine down.

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.kiosk.browserKiosk;

  screenUrlPrefix = "${cfg.originUrl}/screens/";
  pairUrl = "${cfg.originUrl}/pair";

  pythonWithEvdev = pkgs.python3.withPackages (ps: [ ps.evdev ]);

  # Chromium's own offline interstitial (the big white "no internet" page)
  # otherwise shows for however long it takes the network to come up after
  # boot, before ever reaching the pairing/screen URL. This local page loads
  # instantly instead, and redirects to the real target itself as soon as a
  # (no-cors, so cross-origin is fine) fetch to it actually succeeds — a
  # normal top-level navigation to the target follows once we know it's
  # reachable, so Chromium never has to render its own offline page.
  loadingPage = pkgs.writeText "kiosk-loading.html" ''
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        html, body {
          margin: 0;
          height: 100%;
          background: #07090f;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .dot {
          width: 10px;
          height: 10px;
          margin: 0 6px;
          border-radius: 50%;
          background: #14b8a6;
          display: inline-block;
          animation: pulse 1.4s ease-in-out infinite;
        }
        .dot:nth-child(2) { animation-delay: .2s; }
        .dot:nth-child(3) { animation-delay: .4s; }
        @keyframes pulse {
          0%, 80%, 100% { opacity: .25; transform: scale(.8); }
          40% { opacity: 1; transform: scale(1); }
        }
      </style>
    </head>
    <body>
      <div><span class="dot"></span><span class="dot"></span><span class="dot"></span></div>
      <script>
        const target = new URLSearchParams(location.search).get('redirect');
        function tryConnect() {
          fetch(target, { mode: 'no-cors', cache: 'no-store' })
            .then(() => { location.href = target; })
            .catch(() => setTimeout(tryConnect, 1000));
        }
        tryConnect();
      </script>
    </body>
    </html>
  '';

  # Detects connected outputs, enables any that aren't yet active, and
  # launches one Chromium kiosk instance per output at that output's
  # native geometry. Writes "<output> <cdp-port>" pairs to outputs.env
  # so kiosk-url-tracker knows what to poll.
  launcherScript = pkgs.writeShellScript "kiosk-launcher" ''
    set -euo pipefail
    export DISPLAY=:0
    # Relies on the default ~/.Xauthority for $USER's own autologin X
    # session (kiosk-launcher runs as the same user lightdm logs in).

    ${pkgs.xrandr}/bin/xrandr --auto || true
    mkdir -p "${cfg.stateDir}"
    : > "${cfg.stateDir}/outputs.env"

    pids=()
    port=9333
    while read -r name _ geom; do
      [ -n "$name" ] || continue
      w=$(echo "$geom" | grep -oP '^\d+' || true)
      h=$(echo "$geom" | grep -oP '(?<=x)\d+' || true)
      x=$(echo "$geom" | grep -oP '(?<=\+)\d+(?=\+)' || true)
      y=$(echo "$geom" | grep -oP '(?<=\+)\d+$' || true)
      [ -n "$w" ] && [ -n "$h" ] || continue

      profile_dir="${cfg.stateDir}/profile-$name"
      mkdir -p "$profile_dir"
      url_file="$profile_dir/current-url"
      start_url="${pairUrl}"
      if [ -s "$url_file" ]; then
        start_url="$(cat "$url_file")"
      fi

      echo "$name $port" >> "${cfg.stateDir}/outputs.env"

      ${pkgs.chromium}/bin/chromium \
        --user-data-dir="$profile_dir" \
        --remote-debugging-port="$port" \
        --remote-debugging-address=127.0.0.1 \
        --window-position="$x,$y" \
        --window-size="$w,$h" \
        --kiosk \
        --noerrdialogs \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-restore-session-state \
        --autoplay-policy=no-user-gesture-required \
        --check-for-update-interval=31536000 \
        --no-first-run \
        "file://${loadingPage}?redirect=$(jq -rn --arg v "$start_url" '$v|@uri')" &
      pids+=("$!")
      port=$((port + 1))
    done < <(${pkgs.xrandr}/bin/xrandr --query | awk '/ connected/ {geom="0x0+0+0"; for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) geom=$i; print $1, "connected", geom}')

    if [ ''${#pids[@]} -eq 0 ]; then
      echo "kiosk-launcher: no connected outputs found" >&2
      exit 1
    fi

    wait "''${pids[@]}"
  '';

  # Polls each active instance's DevTools port for the current tab URL and
  # persists it once it looks like an assigned screen — this is the only
  # reason a reboot can skip re-pairing, since the app's own /pair page
  # always mints a fresh code regardless of an existing session cookie.
  trackerScript = pkgs.writeShellScript "kiosk-url-tracker" ''
    set -euo pipefail
    while true; do
      if [ -f "${cfg.stateDir}/outputs.env" ]; then
        while read -r name port; do
          [ -n "$name" ] || continue
          url=$(${pkgs.curl}/bin/curl -s "http://127.0.0.1:$port/json" \
            | ${pkgs.jq}/bin/jq -r '.[0].url // empty' 2>/dev/null || true)
          case "$url" in
            "${screenUrlPrefix}"*)
              url_file="${cfg.stateDir}/profile-$name/current-url"
              if [ ! -f "$url_file" ] || [ "$(cat "$url_file")" != "$url" ]; then
                echo -n "$url" > "$url_file"
              fi
              ;;
          esac
        done < "${cfg.stateDir}/outputs.env"
      fi
      sleep 5
    done
  '';

  # Watches the onboard power-button (gpio-keys "pwr_button") and, on
  # press, wipes every kiosk profile's cookies/cache and restarts the
  # launcher so all instances reload to the pairing URL. Resolved by
  # device name rather than a hardcoded /dev/input/eventN path, since
  # event node numbering isn't guaranteed stable across boots.
  resetButtonScript = pkgs.writers.writePython3 "kiosk-reset-button" { } ''
    import glob
    import subprocess
    import time
    from evdev import InputDevice, categorize, ecodes, list_devices

    STATE_DIR = "${cfg.stateDir}"


    def find_pwr_button():
        for path in list_devices():
            dev = InputDevice(path)
            if dev.name == "pwr_button":
                return dev
        return None


    def reset_kiosk():
        print("kiosk-reset-button: resetting all kiosk profiles")
        for profile_dir in glob.glob(f"{STATE_DIR}/profile-*"):
            subprocess.run(["rm", "-rf", f"{profile_dir}/Default"], check=False)
            subprocess.run(["rm", "-f", f"{profile_dir}/current-url"], check=False)
        subprocess.run(
            ["systemctl", "restart", "kiosk-launcher.service"], check=False
        )


    def main():
        dev = None
        while dev is None:
            dev = find_pwr_button()
            if dev is None:
                time.sleep(2)

        print(f"kiosk-reset-button: watching {dev.path} ({dev.name})")
        for event in dev.read_loop():
            if event.type == ecodes.EV_KEY:
                key = categorize(event)
                if key.keycode in ("KEY_POWER",) and key.keystate == key.key_down:
                    reset_kiosk()
                    time.sleep(3)  # debounce


    if __name__ == "__main__":
        main()
  '';
in
{
  options.modules.services.kiosk.browserKiosk = {
    enable = mkEnableOption "Per-HDMI-output Chromium kiosk with reboot-persistent screen URLs and power-button reset";

    originUrl = mkOption {
      type = types.str;
      default = "https://plotiphar.com";
      description = "Base origin of the stage-plotifer app. Pairing is served at <originUrl>/pair, assigned screens at <originUrl>/screens/<id>.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/kiosk";
      description = "Directory holding one Chromium profile (cookies/cache/current-url) per active output.";
    };

    user = mkOption {
      type = types.str;
      default = "kiosk";
      description = "Local user the X session and Chromium instances run as. Created by this module, kept separate from the admin user.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isNormalUser = true;
      extraGroups = [ "video" "input" "audio" "render" ];
    };

    # root:root + sticky-bit-world-writable (same pattern as /tmp) rather than
    # owned by cfg.user — avoids a boot-time race where systemd-tmpfiles-setup
    # runs before the kiosk user is registered, which silently drops a rule
    # that names an as-yet-unresolvable owner and leaves stateDir missing.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 1777 root root -"
    ];

    systemd.services.kiosk-launcher = {
      description = "Per-output Chromium kiosk launcher";
      after = [ "display-manager.service" ];
      wantedBy = [ "multi-user.target" ];
      # Bare `grep`/`awk` calls in launcherScript otherwise fail with
      # "command not found" — systemd units don't inherit an interactive
      # shell's PATH, so external tools need to be listed explicitly.
      path = with pkgs; [ xrandr gnugrep gawk coreutils chromium jq ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${launcherScript}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.kiosk-url-tracker = {
      description = "Persist each kiosk instance's assigned screen URL across reboots";
      after = [ "kiosk-launcher.service" ];
      wants = [ "kiosk-launcher.service" ];
      path = with pkgs; [ curl jq coreutils ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${trackerScript}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.kiosk-reset-button = {
      description = "Reset all kiosk instances to the pairing URL on power-button press";
      wantedBy = [ "multi-user.target" ];
      # resetButtonScript shells out to bare `rm`/`systemctl`.
      path = with pkgs; [ coreutils systemd ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pythonWithEvdev}/bin/python3 ${resetButtonScript}";
        Restart = "on-failure";
        RestartSec = "2s";
        # Needs to read /dev/input/eventN (gpio-keys) and call systemctl.
        SupplementaryGroups = [ "input" ];
      };
    };

    # The power button otherwise triggers systemd-logind's default
    # poweroff handling — kiosk-reset-button.service replaces that
    # behavior entirely, so the default action must be disabled.
    services.logind.settings.Login.HandlePowerKey = "ignore";

    environment.systemPackages = [ pkgs.chromium ];
  };
}
