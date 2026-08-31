#!/usr/bin/env bash
# t2-install — interactive NixOS installer helper for tristons-nixbook-pro
# Run from the live ISO after connecting to WiFi.
#
# What it does:
#   1. Detects the disk and prompts for the Linux allocation partition to replace
#   2. Repartitions it into swap + btrfs
#   3. Creates btrfs subvolumes @, @home, @nix
#   4. Mounts everything at /mnt
#   5. Clones nix-config and generates hardware-configuration.nix
#   6. Runs nixos-install with the soopy.moe T2 kernel cache
#   7. Prompts for user password via nixos-enter

set -euo pipefail

FLAKE_URL="github:TristonYoder/nix-config"
HOST="tristons-nixbook-pro"
SOOPY_CACHE="https://cache.soopy.moe"
SOOPY_KEY="cache.soopy.moe:MzBsBVPllIlCwL2PVs3BQC3Bfbp9TIgakN1xFUDEm8E="

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLD='\033[1m'
RST='\033[0m'

step() { echo -e "\n${BLD}==> $*${RST}"; }
ok()   { echo -e "${GRN}✓${RST} $*"; }
warn() { echo -e "${YLW}⚠${RST}  $*"; }
die()  { echo -e "${RED}✗${RST}  $*" >&2; exit 1; }

# ── Prerequisites ─────────────────────────────────────────────────────────────

echo -e "\n${BLD}T2 MacBook Pro — NixOS Installer${RST}"
echo "──────────────────────────────────────────"

[[ $EUID -eq 0 ]] || die "Run as root: sudo t2-install"

step "Checking connectivity"
if ping -c1 -W3 cache.nixos.org &>/dev/null; then
  ok "Network reachable"
else
  warn "No network detected. Connect to WiFi first:"
  echo "    nmcli device wifi list"
  echo "    nmcli device wifi connect 'SSID' password 'PASS'"
  echo ""
  read -rp "Continue anyway? [y/N] " cont
  [[ $cont =~ ^[Yy]$ ]] || exit 0
fi

# ── Disk selection ─────────────────────────────────────────────────────────────

step "Current disk layout"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT /dev/nvme0n1 2>/dev/null || lsblk

echo ""
read -rp "Target disk [/dev/nvme0n1]: " DISK
DISK="${DISK:-/dev/nvme0n1}"
[[ -b "$DISK" ]] || die "Block device not found: $DISK"

echo ""
echo "Partition table for $DISK:"
parted -s "$DISK" print || true

echo ""
warn "Identify the ExFAT partition you created in macOS Disk Utility."
warn "That partition will be DELETED and replaced with swap + btrfs."
read -rp "Linux allocation partition number (e.g. 3): " PART_NUM
[[ "$PART_NUM" =~ ^[0-9]+$ ]] || die "Expected a number"

LINUX_PART="${DISK}p${PART_NUM}"
[[ -b "$LINUX_PART" ]] || die "Partition not found: $LINUX_PART"

# ── Swap size ─────────────────────────────────────────────────────────────────

RAM_GB=$(awk '/MemTotal/ { printf "%d", $2 / 1024 / 1024 }' /proc/meminfo)
if   (( RAM_GB >= 32 )); then DEFAULT_SWAP="32G"
elif (( RAM_GB >= 16 )); then DEFAULT_SWAP="16G"
else                          DEFAULT_SWAP="8G"
fi

echo ""
echo "Detected RAM: ${RAM_GB}GB"
read -rp "Swap size [${DEFAULT_SWAP}]: " SWAP_SIZE
SWAP_SIZE="${SWAP_SIZE:-$DEFAULT_SWAP}"

SWAP_PART="${DISK}p${PART_NUM}"
BTRFS_PART="${DISK}p$((PART_NUM + 1))"

# ── Confirm ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${YLW}Actions that will be taken:${RST}"
echo "  DELETE  $LINUX_PART (${SWAP_SIZE} ExFAT → replaced)"
echo "  CREATE  ${DISK}p${PART_NUM}  — ${SWAP_SIZE} swap"
echo "  CREATE  ${DISK}p$((PART_NUM+1)) — btrfs root (rest)"
echo "  FORMAT  swap, btrfs"
echo "  MOUNT   btrfs subvolumes + EFI at /mnt"
echo "  INSTALL nixos from ${FLAKE_URL}#${HOST}"
echo ""
echo -e "${RED}This is destructive. The ExFAT partition will be erased.${RST}"
read -rp "Proceed? [y/N] " confirm
[[ $confirm =~ ^[Yy]$ ]] || exit 0

# ── Repartition ───────────────────────────────────────────────────────────────

step "Repartitioning $DISK"

PART_START=$(parted -s "$DISK" unit MiB print \
  | awk "/ ${PART_NUM} /{print \$2}" \
  | tr -d 'MiB')

parted -s "$DISK" rm "$PART_NUM"
parted -s "$DISK" mkpart swap linux-swap "${PART_START}MiB" "+${SWAP_SIZE}"
parted -s "$DISK" mkpart nixos btrfs "+0" "100%"
partprobe "$DISK"
sleep 1

ok "Partitions created"

SWAP_PART="${DISK}p${PART_NUM}"
BTRFS_PART="${DISK}p$((PART_NUM + 1))"

[[ -b "$SWAP_PART"  ]] || die "Swap partition not found: $SWAP_PART"
[[ -b "$BTRFS_PART" ]] || die "Btrfs partition not found: $BTRFS_PART"

# ── Format ────────────────────────────────────────────────────────────────────

step "Formatting partitions"
mkswap -L swap "$SWAP_PART"
mkfs.btrfs -L nixos "$BTRFS_PART"
ok "Formatted"

# ── Btrfs subvolumes ──────────────────────────────────────────────────────────

step "Creating btrfs subvolumes"
mount "$BTRFS_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
umount /mnt
ok "Subvolumes: @, @home, @nix"

# ── Mount ─────────────────────────────────────────────────────────────────────

step "Mounting filesystems"

BTRFS_OPTS="compress=zstd,noatime"

mount -o "subvol=@,${BTRFS_OPTS}"     "$BTRFS_PART" /mnt
mkdir -p /mnt/{home,nix,boot}
mount -o "subvol=@home,${BTRFS_OPTS}" "$BTRFS_PART" /mnt/home
mount -o "subvol=@nix,${BTRFS_OPTS}"  "$BTRFS_PART" /mnt/nix
swapon "$SWAP_PART"

# Find and mount EFI — look for the vfat partition with an EFI/ directory
EFI_PART="${DISK}p1"
if [[ -b "$EFI_PART" ]]; then
  mount "$EFI_PART" /mnt/boot
  if ls /mnt/boot/EFI/ &>/dev/null; then
    ok "Mounted $EFI_PART at /boot (existing macOS EFI)"
  else
    warn "$EFI_PART doesn't look like an EFI partition — check /mnt/boot manually"
  fi
else
  warn "Could not find $EFI_PART. Mount the EFI partition manually at /mnt/boot."
  read -rp "Press Enter once /mnt/boot is mounted: "
fi

ok "All filesystems mounted at /mnt"

# ── Hardware config ───────────────────────────────────────────────────────────

step "Generating hardware configuration"

HWCONFIG=/tmp/hardware-configuration.nix
nixos-generate-config --root /mnt --show-hardware-config > "$HWCONFIG"

echo ""
echo "Generated hardware-configuration.nix:"
echo "────────────────────────────────────────"
cat "$HWCONFIG"
echo "────────────────────────────────────────"
echo ""
warn "You need to commit this to nix-config before installing."
echo ""
echo "Option A — update from another machine and commit to GitHub:"
echo "  1. Copy the output above into hosts/tristons-nixbook-pro/hardware-configuration.nix"
echo "  2. Commit and push to main"
echo "  3. Press Enter here to continue (nixos-install pulls from GitHub)"
echo ""
echo "Option B — clone locally and edit on this machine:"
echo "  nixos-install will clone /mnt/etc/nixos/nix-config from GitHub"
echo "  You can then edit hardware-configuration.nix there and re-run."
echo ""
read -rp "Press Enter when hardware-configuration.nix is committed to GitHub: "

# ── Install ───────────────────────────────────────────────────────────────────

step "Running nixos-install"

nixos-install \
  --root /mnt \
  --flake "${FLAKE_URL}#${HOST}" \
  --option extra-substituters "$SOOPY_CACHE" \
  --option extra-trusted-public-keys "$SOOPY_KEY" \
  --no-root-passwd

ok "nixos-install complete"

# ── User password ─────────────────────────────────────────────────────────────

step "Set user password"
echo "Setting password for tristonyoder:"
nixos-enter --root /mnt -c "passwd tristonyoder"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GRN}${BLD}Installation complete!${RST}"
echo ""
echo "Reboot and hold Option (⌥) at startup → select 'Linux Boot Manager'."
echo ""
echo "After first boot:"
echo "  • WiFi: should work immediately (firmware baked in)"
echo "  • Rebuild: sudo nixos-rebuild switch --flake /etc/nixos/nix-config#${HOST}"
echo "  • Suspend: handled automatically by t2-apple-bce-suspend service"
echo ""
read -rp "Reboot now? [y/N] " reboot_now
[[ $reboot_now =~ ^[Yy]$ ]] && reboot
