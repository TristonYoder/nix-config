# Shared logic for every barebones installer variant (x86_64/aarch64 ISO,
# Raspberry Pi 5 sdImage): key-only SSH and Tailscale (headscale) auto-join
# with a boot-time QR code. See configuration.nix for the x86_64/aarch64 ISO
# entry point and rpi5.nix for the Pi 5 sdImage entry point — both import
# this file rather than duplicating it.
{ lib, pkgs, ... }:
let
  # Cached here so it survives past the scrolling boot log — printed again
  # by environment.interactiveShellInit below every time a shell/terminal
  # starts, not just once during the systemd unit's boot-time output.
  qrCacheFile = "/run/tailscale-qr.txt";

  tailscaleUp = pkgs.writeShellScript "tailscale-autoconnect" ''
    set -eu

    urlFile=$(mktemp)
    trap 'rm -f "$urlFile"' EXIT

    # Run `tailscale up` in the background and tee its output so we can
    # grab the headscale login URL as soon as it's printed, without
    # blocking on the auth wait before we've shown the QR code.
    # NOTE: `--ephemeral` is not a valid flag for `tailscale up` on the
    # currently-deployed tailscale version (1.98.5) — it errors with "flag
    # provided but not defined", which prints tailscale's help text to
    # stdout instead of logging in. The script below then greps that help
    # text for a URL and picks up the default `https://controlplane.tailscale.com`
    # mentioned there instead of the real headscale registration URL,
    # producing a QR code that goes nowhere. The installer environment is
    # still throwaway (RAM-only, gone on reboot), but since this installer
    # never embeds an authkey, ephemeral-node behavior isn't achievable via
    # `up` flags on this version — it would need an ephemeral-tagged authkey
    # instead. Headscale will accumulate a stale "nixos-installer" entry
    # per boot until that's added.
    ${lib.getExe' pkgs.tailscale "tailscale"} up \
      --login-server=https://ts.theyoder.family \
      --ssh \
      --hostname=nixos-installer \
      2>&1 | tee "$urlFile" &
    tsPid=$!

    url=""
    for _ in $(seq 1 30); do
      url=$(grep -oE 'https://[^ ]+' "$urlFile" | head -n1 || true)
      [ -n "$url" ] && break
      sleep 1
    done

    if [ -n "$url" ]; then
      {
        echo ""
        echo "Scan to join the tailnet: $url"
        echo ""
        ${lib.getExe pkgs.qrencode} -t ANSIUTF8 "$url"
      } | tee ${qrCacheFile}
    fi

    wait "$tsPid"
  '';
in
{
  networking.hostName = lib.mkDefault "nixos-installer";

  # Key-only SSH — no passwords baked into a public image.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz"
  ];

  services.tailscale.enable = true;

  # Re-print the cached QR code/URL (see qrCacheFile above) whenever a shell
  # starts — the autologin console shell on boot, or reconnecting to tty1 —
  # so it's still there once the terminal has settled, not just a one-shot
  # flash buried in the scrolling boot log.
  environment.interactiveShellInit = ''
    cat ${qrCacheFile} 2>/dev/null || true
  '';

  # No authkey embedded (public repo). tailscale-autoconnect prints the
  # headscale login URL (and a QR code) to the console on boot — open it,
  # or scan it, on another device to authorize the node, then SSH to it
  # over the tailnet.
  systemd.services.tailscale-autoconnect = {
    description = "Join the Tailscale (headscale) tailnet on boot";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
      ExecStart = "${tailscaleUp}";
    };
  };
}
