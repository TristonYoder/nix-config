# Installing NixOS on the T2 MacBook Pro (tristons-nixbook-pro)

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
3. Add a new partition: format **ExFAT**, size however much you want for Linux (≥80GB recommended; this guide uses the full remaining space)
4. Click Apply

> Do not use Disk Utility's "Erase" on the whole disk — that removes macOS.

The ExFAT partition will be replaced by a swap partition and a btrfs root partition during installation.

---

## 2. Build and write the custom installer ISO

The custom ISO has the T2 kernel and WiFi firmware baked in — WiFi works on first boot
with no ethernet or USB adapter needed.

Run these commands from the `nix-config` repo root on **tyoder-mbp**:

```bash
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Build the minimal ISO on david (x86_64-linux builder)
# WiFi firmware is fetched automatically from macOS Sonoma at build time.
nix build .#nixosConfigurations.tristons-nixbook-pro-installer.config.system.build.isoImage \
  --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
  --option extra-substituters "https://cache.soopy.moe" \
  --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

# Or build the Plasma 6 ISO (larger, has GUI installer):
nix build .#nixosConfigurations.tristons-nixbook-pro-installer-plasma.config.system.build.isoImage \
  --builders "ssh://tristonyoder@david x86_64-linux - 4 - - nixos-test,benchmark,big-parallel,kvm" \
  --option extra-substituters "https://cache.soopy.moe" \
  --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="
```

Write to USB (replace `diskN` with the correct disk from `diskutil list`):

```bash
diskutil list
sudo diskutil unmountDisk /dev/diskN
sudo dd if=result/iso/nixos-t2-macbookpro16.iso of=/dev/rdiskN bs=4m status=progress
```

Boot from USB: hold **Option (⌥)** at startup → select the orange EFI boot entry.

---

## 3. Partition setup in the live environment

The typical T2 Mac layout (MacBookPro16,1) looks like:
```
nvme0n1p1  300MB   EFI (vfat)  ← shared with macOS, mount at /boot
nvme0n1p2  ~466GB  APFS        ← macOS, do not touch
nvme0n1p3  rest    ExFAT       ← the partition you created; repartition below
```

Repartition the Linux partition into swap + btrfs:

```bash
# Delete the ExFAT partition and create swap + btrfs in its place
# (adjust partition number if your layout differs)
sudo parted -s /dev/nvme0n1 rm 3
sudo parted -s /dev/nvme0n1 mkpart swap linux-swap 501GB 570GB   # ~64GiB swap
sudo parted -s /dev/nvme0n1 mkpart nixos btrfs 570GB 100%        # rest for btrfs

# Format
sudo mkswap -L swap /dev/nvme0n1p3
sudo mkfs.btrfs -L nixos /dev/nvme0n1p4
```

Create btrfs subvolumes:

```bash
sudo mount /dev/nvme0n1p4 /mnt
sudo btrfs subvolume create /mnt/@
sudo btrfs subvolume create /mnt/@home
sudo btrfs subvolume create /mnt/@nix
sudo umount /mnt
```

Mount everything:

```bash
sudo mount -o subvol=@,compress=zstd,noatime /dev/nvme0n1p4 /mnt
sudo mkdir -p /mnt/{home,nix,boot}
sudo mount -o subvol=@home,compress=zstd,noatime /dev/nvme0n1p4 /mnt/home
sudo mount -o subvol=@nix,compress=zstd,noatime /dev/nvme0n1p4 /mnt/nix
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo swapon /dev/nvme0n1p3
```

Verify the EFI partition already has macOS boot files:
```bash
ls /mnt/boot/EFI/    # Should show Apple/, boot/, or similar
```

---

## 4. Install NixOS

```bash
# Clone the nix-config repo
sudo mkdir -p /mnt/etc/nixos
sudo git clone https://github.com/TristonYoder/nix-config /mnt/etc/nixos/nix-config

# Generate hardware configuration to get real partition UUIDs
nixos-generate-config --root /mnt --show-hardware-config
```

Copy the generated output and update
`hosts/tristons-nixbook-pro/hardware-configuration.nix` with the real UUIDs.
Commit and push that change, then pull it in the live environment:

```bash
sudo git -C /mnt/etc/nixos/nix-config pull
```

Install:
```bash
sudo nixos-install \
  --flake /mnt/etc/nixos/nix-config#tristons-nixbook-pro \
  --root /mnt \
  --option extra-substituters "https://cache.soopy.moe" \
  --option extra-trusted-public-keys "cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="
```

Set a user password before rebooting (no password is set declaratively):
```bash
sudo nixos-enter --root /mnt
passwd tristonyoder
exit
```

Then reboot and hold **Option (⌥)** → select **Linux Boot Manager**.

---

## 5. Post-installation

### 5a. WiFi

WiFi firmware is baked into the live ISO and deployed automatically during `nixos-install`.
WiFi should work immediately after first boot — no additional steps needed.

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

```bash
sudo nixos-rebuild switch --flake /etc/nixos/nix-config#tristons-nixbook-pro
```

The T2 kernel is cached at `https://cache.soopy.moe` — rebuilds fetch the
pre-built kernel instead of compiling locally.
