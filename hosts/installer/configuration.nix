# Barebones NixOS installer ISO — generic hardware, no host-specific drivers.
#
# Boots to a minimal shell, auto-joins the Tailscale (headscale) tailnet, and
# enables key-only SSH. No authkey is embedded (this repo is public) — on
# first boot `tailscale up` prints a login URL to the console (as text and
# as a scannable QR code); open it on another device — e.g. scan the QR
# with a phone — to authorize the node into the tailnet. Once it's joined,
# SSH in over Tailscale using the key below and drive `nixos-install`
# remotely (partition, format, nixos-generate-config, install) per the
# remote-install workflow in the host-provisioner skill.
#
# Build (from a NixOS host, e.g. david):
#   nix build .#nixosConfigurations.installer.config.system.build.isoImage --refresh
#
# Find the node once it joins the tailnet:
#   ssh admin@ts.theyoder.family    # or check the headscale admin UI
#   ssh root@<hostname>.<tailnet-domain>
{ lib, pkgs, modulesPath, ... }:
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
  imports = [
    # Minimal installer base: no GUI, gives a shell with nixos-install available
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  nixpkgs.config.allowUnfree = true;

  networking.hostName = "nixos-installer";

  # Key-only SSH — no passwords baked into a public ISO image.
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

  isoImage.isoName = lib.mkForce "nixos-installer-barebones.iso";
}
