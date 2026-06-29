---
name: host-provisioner
description: >
  Step-by-step expert for adding new NixOS or macOS hosts to the TristonYoder/nix-config repo. Use when adding a new machine, doing a first install, generating hardware config, registering in flake.nix, or doing a remote install over SSH.
---

# Host Provisioner — TristonYoder/nix-config

You guide the process of adding new managed hosts to this repository.
Read `references/checklist.md` for the full step-by-step checklists.

## Host types

| Type | Profile | flake.nix key | Notes |
|---|---|---|---|
| NixOS server | profiles/server.nix | nixosConfigurations | david-style full stack |
| NixOS desktop | profiles/desktop.nix | nixosConfigurations | KDE Plasma workstation |
| NixOS laptop | profiles/desktop.nix | nixosConfigurations | Same as desktop + battery modules |
| macOS | profiles/darwin.nix | darwinConfigurations | Home Manager + Homebrew |
| NixOS edge | profiles/edge.nix | nixosConfigurations | Lightweight reverse proxy |

## Quick decision tree

1. **Is there an existing machine to SSH into for the install?** → Use remote install technique (see checklist.md)
2. **Is it a T2 MacBook?** → Needs `nixos-hardware.apple-t2` input + special bootloader
3. **Does it have an NVIDIA GPU?** → Needs `modules/hardware/nvidia.nix` (open kernel modules)
4. **Will it mount /home or /data from NFS?** → Set `useDataDrive = true` in user options; add NFS mount config (see tristons-workstation pattern)
5. **Will it run server services?** → Import profiles/server.nix; enable modules per CLAUDE.md architecture

## First things to do after adding a host config

1. Add the host's SSH public key to `secrets/secrets.nix` as a recipient
2. Re-encrypt any secrets the host needs (see nix-secret-manager skill)
3. Enable GitHub Actions runner if this host should be in CI:
   `modules.services.development.github-actions.enable = true;`
4. Add host-specific vHosts entries or module enables
5. Test with dry-run before first real build

## Live installer OOM prevention

Heavy profiles (gaming module, DaVinci Resolve) can OOM a swapless live USB. Always:
```bash
# Check swap before starting
free -h   # Swap line should not be all zeros

# If no swap, create one on the target disk
sudo btrfs filesystem mkswapfile --size 16G /mnt/swapfile
sudo swapon /mnt/swapfile
```

Disable the gaming module in the host config before first install; re-enable post-install.

## After first successful boot

1. Generate final hardware config if needed: `nixos-generate-config --show-hardware-config`
2. Enable any services that were disabled for the install
3. Add the host to GitHub Actions matrix if applicable
4. Sync secrets to the new host

## Key patterns from existing hosts

- **tristons-workstation**: NFS-backed `/home` via `/data` symlink. `useDataDrive = true`. Dual-NIC setup where `network-online.target` may fire on the wrong NIC before the NFS route is available — see CLAUDE.md NFS automount troubleshooting before touching boot-time network ordering.
- **tristons-nixbook-pro**: T2 MacBook, uses `nixos-hardware.apple-t2`. Dual-boot aware; custom installer ISOs are built from the flake.
- **pits**: Lightweight edge profile — no home-manager complexity, minimal module set.
- **david**: Full server stack; is also the CI build host for other machines.

## Secrets checklist for new hosts

Every host that needs to decrypt agenix secrets must:
1. Have its SSH host public key listed in `secrets/secrets.nix`
2. Have all needed secrets re-encrypted including the new host as recipient
3. Declare secrets in `modules/secrets.nix` with correct `owner` and `group`

To get an SSH host public key before the host is installed:
```bash
# From a running live USB on the target
cat /etc/ssh/ssh_host_ed25519_key.pub
# or after install
ssh-keyscan -t ed25519 <hostname-or-ip>
```
