# Installing NixOS on the T2 MacBook Pro (tristons-nixbook-t2)

Dual-boot setup alongside macOS. NixOS uses the same EFI partition that macOS created.

---

## 1. macOS pre-installation (do this first, while macOS still works)

### 1a. Disable Secure Boot

1. Shut down the Mac
2. Boot into Recovery: hold **Power** while powering on (or **⌘R** on older T2 Macs)
3. Open **Utilities → Startup Security Utility**
4. Set **Secure Boot** → "No Security"
5. Set **Allowed Boot Media** → "Allow booting from external or removable media"
6. Restart

This permanently disables Touch ID on Linux (T2 Secure Enclave is unavailable).

### 1b. Partition the disk

Use **Disk Utility** in macOS to shrink the APFS container:

1. Open **Disk Utility** → View → Show All Devices
2. Select the APFS Container, click **Partition**
3. Add a new partition: format **ExFAT**, size however much you want for Linux (≥40GB recommended)
4. Click Apply

> Do not use Disk Utility's "Erase" on the whole disk — that removes macOS.

The new ExFAT partition will become the Linux root partition. You'll reformat it to ext4 during installation.

---

## 2. Build and write the custom installer ISO

The custom ISO has the T2 kernel and WiFi firmware baked in — WiFi works on first boot
with no ethernet or USB adapter needed.

Run these commands from the `nix-config` repo root on **tyoder-mbp**:

```bash
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Build the ISO on david (x86_64-linux builder)
# WiFi firmware is fetched automatically from macOS Sonoma at build time.
nix build .#nixosConfigurations.tristons-nixbook-t2-installer.config.system.build.isoImage \
  --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
  --option extra-substituters "https://cache.soopy.moe" \
  --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

# result/iso/nixos-t2-macbookpro16.iso is a symlink to the built ISO
```

Write to USB (replace `diskN` with the correct disk from `diskutil list`):

```bash
diskutil list
sudo diskutil unmountDisk /dev/diskN
sudo dd if=result/iso/nixos-t2-macbookpro16.iso of=/dev/rdiskN bs=4m status=progress
```

Boot from USB: hold **Option (⌥)** at startup → select the orange EFI boot entry.

> The ISO is built with `--impure`, meaning the firmware tarball is pulled from
> `/tmp/t2-wifi-firmware.tar.gz` at evaluation time. Clean it up afterwards:
> `rm /tmp/t2-wifi-firmware.tar.gz`

---

## 3. Partition setup in the live environment

```bash
# Identify your disks
lsblk
# NVMe SSD is typically /dev/nvme0n1
# USB installer is typically /dev/sda or /dev/sdb

# View current partition layout
fdisk -l /dev/nvme0n1
```

The typical T2 Mac layout looks like:
```
nvme0n1p1  200MB   EFI  ← shared with macOS, mount at /boot
nvme0n1p2  ...     macOS Recovery
nvme0n1p3  ...     APFS (macOS)
nvme0n1p4  ...     ExFAT ← the partition you created; reformat to ext4
```

```bash
# Format the Linux partition to ext4 with label "nixos"
mkfs.ext4 -L nixos /dev/nvme0n1p4

# Mount the new root
mount /dev/nvme0n1p4 /mnt

# Mount the EFI partition (shared with macOS — do NOT format it)
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
```

Verify the EFI partition already has macOS boot files:
```bash
ls /mnt/boot/EFI/    # Should show Apple/, boot/, or similar
```

---

## 4. Install NixOS

```bash
# If /tmp fills up during kernel build, bind-mount the root fs
mount --bind /mnt/tmp /tmp

# Clone the nix-config repo
nix-shell -p git --run "git clone https://github.com/TristonYoder/nix-config /mnt/etc/nixos/nix-config"

# Generate hardware configuration (this produces the UUIDs you need)
nixos-generate-config --root /mnt --show-hardware-config
```

Copy the generated `hardware-configuration.nix` output and update
`hosts/tristons-nixbook-t2/hardware-configuration.nix` with the real UUIDs.
Commit and push that change, then pull it in the live environment:

```bash
cd /mnt/etc/nixos/nix-config
git pull
```

Install:
```bash
nixos-install --flake /mnt/etc/nixos/nix-config#tristons-nixbook-t2 --root /mnt
```

Set the root password when prompted, then reboot.

---

## 5. Post-installation

### 5a. WiFi

WiFi firmware is deployed by the `t2-wifi-firmware` activation script during rebuild.
After first boot, run a rebuild to trigger activation (connect via ethernet or USB tethering):

```bash
sudo nixos-rebuild switch --flake /etc/nixos/nix-config#tristons-nixbook-t2
```

After the rebuild completes, WiFi should appear in network settings. If the firmware
was already deployed before install, WiFi works immediately.

### 5b. Verify hardware

```bash
# Keyboard and trackpad
evtest   # should list apple-bce devices

# WiFi
ip link   # look for wlpXs0 or wlan0
nmcli device wifi list

# Audio
pactl info
aplay -l

# Touch Bar
# Appears as a function key row — no special configuration needed
```

### 5c. Known issues

| Issue | Status | Fix |
|-------|--------|-----|
| Suspend/resume | Broken with macOS Sonoma firmware | Handled by `t2-apple-bce-suspend` systemd service (automatic) |
| Touch ID | Not supported | T2 Secure Enclave unavailable on Linux |
| Touch Bar gestures | Not supported | Functions as F1–F12 + media keys |
| Trackpad force touch | Not supported | Left/right click work normally |

---

## Rebuilding after install

Once installed, rebuild from the repo as normal:

```bash
sudo nixos-rebuild switch --flake /etc/nixos/nix-config#tristons-nixbook-t2
```

Or use the `rebuild` alias if it's been configured in the shell.

The T2 kernel is cached at `https://cache.soopy.moe` — rebuilds fetch the
pre-built kernel instead of compiling locally.
