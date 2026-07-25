# Barebones NixOS installer ISO — generic hardware, no host-specific drivers.
# Two architectures (x86_64-linux, aarch64-linux) share this file; see
# rpi5.nix for the Raspberry Pi 5 sdImage variant, which needs Pi-specific
# hardware modules this generic ISO doesn't. Both import common.nix for the
# shared Tailscale/SSH/QR logic.
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
  # Clear per-architecture label for the built ISO's filename — keeps
  # x86_64/aarch64/rpi5 unambiguous when they sit side by side in a
  # downloads directory.
  archLabel =
    { x86_64-linux = "x86_64"; aarch64-linux = "aarch64"; }
    .${pkgs.stdenv.hostPlatform.system} or pkgs.stdenv.hostPlatform.system;
in
{
  imports = [
    # Minimal installer base: no GUI, gives a shell with nixos-install available
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ./common.nix
  ];

  nixpkgs.config.allowUnfree = true;

  isoImage.isoName = lib.mkForce "nixos-installer-${archLabel}.iso";
}
