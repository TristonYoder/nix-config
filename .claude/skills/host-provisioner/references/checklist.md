# Host Provisioner Checklists

## Adding a NixOS host

### Step 1: Create host config
```bash
mkdir -p hosts/<hostname>
```

Create `hosts/<hostname>/configuration.nix`:
```nix
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    ../../profiles/server.nix   # or desktop.nix / edge.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "<hostname>";
  networking.domain   = "theyoder.family";   # or your domain

  # Host-specific module enables
  modules.services.media.jellyfin.enable = true;
  # etc.
}
```

### Step 2: Register in flake.nix
```nix
nixosConfigurations."<hostname>" = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";   # or aarch64-linux
  specialArgs = { inherit inputs; };
  modules = [
    ./hosts/<hostname>/configuration.nix
    home-manager.nixosModules.home-manager
    agenix.nixosModules.default
    ./modules/secrets.nix
  ];
};
```

### Step 3: Generate hardware config (on target machine)
```bash
nixos-generate-config --root /mnt   # during install, from live USB
# or on a running system:
nixos-generate-config --show-hardware-config > hosts/<hostname>/hardware-configuration.nix
```

### Step 4: Add to secrets recipients
In `secrets/secrets.nix`, add the host SSH key:
```nix
let
  newhost = "ssh-ed25519 AAAA...";  # get with: ssh-keyscan -t ed25519 <host>
```
Then re-encrypt any secrets the host needs using `encrypt-secret.sh`.

### Step 5: First build
```bash
# Push branch first, then test
ssh github-actions@david.vpn.theyoder.family \
  "sudo nixos-rebuild dry-run --flake 'github:TristonYoder/nix-config/<branch>#<hostname>' --refresh"
```

---

## Adding a macOS (Darwin) host

### Step 1: Create host config
`hosts/<hostname>/configuration.nix`:
```nix
{ config, lib, pkgs, ... }:
{
  imports = [ ../../profiles/darwin.nix ];

  networking.hostName    = "<hostname>";
  networking.computerName = "<Display Name>";
}
```

### Step 2: Register in flake.nix
```nix
darwinConfigurations."<hostname>" = darwin.lib.darwinSystem {
  system = "aarch64-darwin";   # or x86_64-darwin for Intel
  specialArgs = { inherit inputs; };
  modules = [
    ./hosts/<hostname>/configuration.nix
    home-manager-unstable.darwinModules.home-manager
    agenix.darwinModules.default
  ];
};
```

### Step 3: First build
```bash
# On the Mac itself — first time when nix-darwin not yet installed:
nix build '.#darwinConfigurations.<hostname>.config.system.build.toplevel' --out-link /tmp/result
sudo /tmp/result/sw/bin/darwin-rebuild switch --flake 'github:TristonYoder/nix-config#<hostname>'

# Subsequent rebuilds:
rebuild   # or: darwin-rebuild switch --refresh --flake github:TristonYoder/nix-config
```

---

## Remote NixOS install (over SSH, no physical access)

Used when the target machine can be booted into a NixOS live ISO via IPMI/iDRAC/VNC.

1. Boot target into NixOS live USB or netboot
2. On target: `passwd nixos && systemctl start sshd`
3. From local machine, copy your SSH key: `ssh-copy-id -i ~/.ssh/id_ed25519.pub nixos@<target-ip>`
4. Partition and format disks on target
5. Mount target root at /mnt: `mount /dev/disk/... /mnt`
6. Generate hardware config: `nixos-generate-config --root /mnt`
7. Copy generated hardware-configuration.nix into repo
8. Add swap if heavy profile: `sudo btrfs filesystem mkswapfile --size 16G /mnt/swapfile && sudo swapon /mnt/swapfile`
9. Run install: `nixos-install --flake 'github:TristonYoder/nix-config#<hostname>' --refresh`
10. Reboot: `reboot`

**OOM warning:** heavy profiles (gaming module, DaVinci Resolve) can exhaust RAM in a swapless live environment. Always run `free -h` before starting; create a swapfile if Swap shows 0B.

**If install is interrupted:** already-built store paths under `/mnt/nix/store` survive a reboot of the live session as long as partitions aren't reformatted — remount and resume.

---

## T2 MacBook (nixos-hardware)

Add to flake inputs:
```nix
nixos-hardware.url = "github:NixOS/nixos-hardware/master";
```

Add to host imports:
```nix
imports = [
  nixos-hardware.nixosModules.apple-t2
  ../../profiles/desktop.nix
  ./hardware-configuration.nix
];
```

The T2 chip requires a specific kernel; `nixos-hardware.apple-t2` handles this automatically. Dual-boot with macOS requires care with the EFI partition — don't let nixos-install touch the EFI partition if macOS is already there.

---

## GitHub Actions CI integration

To include a host in CI builds, enable the runner module:
```nix
modules.services.development.github-actions.enable = true;
```

The CI matrix job (`.github/workflows/`) will automatically pick up new hosts registered in `nixosConfigurations` in flake.nix.

To add a new host to the workflow matrix, add it to the matrix list in `.github/workflows/deploy.yml` (or equivalent). Look for the existing host list to find the right format.

---

## Post-install checklist

- [ ] Host boots successfully
- [ ] SSH accessible
- [ ] `nixos-generate-config --show-hardware-config` matches what's in repo (or update it)
- [ ] Secrets decrypt correctly: `ls /run/agenix/`
- [ ] Any disabled-for-install modules re-enabled and rebuilt
- [ ] Host added to GitHub Actions matrix if it will be a CI builder
- [ ] `rebuild` alias works from the host itself
