#!/usr/bin/env bash
# Migrate a user from the useDataDrive layout (all of /home/<user> symlinked
# onto shared storage) to the homeSplit layout (host-local home, shared paths
# symlinked in).
#
# Run this ONCE PER HOST, for each user, BEFORE rebuilding onto a configuration
# that sets modules.system.users.homeSplit.enable. The rebuild creates the
# shared symlinks; this script populates the local home with everything that is
# NOT shared, and clears the old whole-home symlink out of the way.
#
# The shared path list is read from the flake, not duplicated here, so it can
# never drift from modules/system/home-split.nix.
#
# Nothing under the shared root is deleted or moved. The old dotfiles stay
# where they are, which is what makes this reversible: to roll back, remove the
# local home and rebuild the previous generation.
#
# Usage:
#   ./migrate-home-split.sh --user tristonyoder                 # dry run
#   ./migrate-home-split.sh --user tristonyoder --apply
#   ./migrate-home-split.sh --user tristonyoder --apply --btrfs-subvol @tristonyoder-home
#
# --btrfs-subvol reuses/creates a dedicated btrfs subvolume for the local home
# (tristons-workstation). Omit it on hosts where the local home is a plain
# directory on the root filesystem (david).

set -euo pipefail

FLAKE="${FLAKE:-github:TristonYoder/nix-config/feat/home-split}"
SHARED_ROOT="/data"
USER_NAME=""
APPLY=0
SUBVOL=""
BTRFS_DEV=""

die() { echo "error: $*" >&2; exit 1; }
run() {
  if [[ "$APPLY" -eq 1 ]]; then
    echo "  + $*"
    "$@"
  else
    echo "  would run: $*"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)         USER_NAME="$2"; shift 2 ;;
    --apply)        APPLY=1; shift ;;
    --btrfs-subvol) SUBVOL="$2"; shift 2 ;;
    --btrfs-device) BTRFS_DEV="$2"; shift 2 ;;
    --flake)        FLAKE="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$USER_NAME" ]] || die "--user is required"
[[ "$(id -u)" -eq 0 ]] || die "must run as root (sudo)"

HOSTNAME_SHORT="$(hostname)"
LOCAL_HOME="/home/${USER_NAME}"
SHARED_HOME="${SHARED_ROOT}/${USER_NAME}/home"

echo "==> host=${HOSTNAME_SHORT} user=${USER_NAME}"
echo "    local home:  ${LOCAL_HOME}"
echo "    shared home: ${SHARED_HOME}"
[[ "$APPLY" -eq 1 ]] || echo "    (dry run -- pass --apply to execute)"
echo

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

[[ -d "$SHARED_HOME" ]] || die "shared home ${SHARED_HOME} is not a directory (is /data mounted?)"

if [[ -e "$LOCAL_HOME" && ! -L "$LOCAL_HOME" ]]; then
  die "${LOCAL_HOME} already exists as a real directory -- this host looks migrated already"
fi

# Refuse to move a home out from under a live session. A running Plasma session
# holds open file descriptors all over ~/.config and ~/.local; migrating
# underneath it produces a half-written profile and an unrecoverable desktop.
if loginctl list-sessions --no-legend 2>/dev/null \
     | awk -v u="$USER_NAME" '$3 == u { print }' | grep -q .; then
  echo "Active sessions for ${USER_NAME}:" >&2
  loginctl list-sessions --no-legend | awk -v u="$USER_NAME" '$3 == u { print "  " $0 }' >&2
  die "log ${USER_NAME} out fully (including the graphical session) before migrating"
fi

# ---------------------------------------------------------------------------
# Shared paths, read from the flake so this can't drift from the module
# ---------------------------------------------------------------------------

echo "==> reading shared paths from ${FLAKE}"
attr="nixosConfigurations.${HOSTNAME_SHORT}.config.modules.system.users.homeSplit.users.\"${USER_NAME}\""
mapfile -t SHARED_PATHS < <(
  nix eval --refresh --raw "${FLAKE}#${attr}.sharedPaths" \
    --apply 'builtins.concatStringsSep "\n"'
)
mapfile -t SHARED_FILES < <(
  nix eval --refresh --raw "${FLAKE}#${attr}.sharedFiles" \
    --apply 'builtins.concatStringsSep "\n"'
)

printf '    shared dir:  %s\n' "${SHARED_PATHS[@]}"
printf '    shared file: %s\n' "${SHARED_FILES[@]}"
echo

# ---------------------------------------------------------------------------
# Prepare the local home (btrfs subvolume, or a plain directory)
# ---------------------------------------------------------------------------

STAGING="/var/tmp/home-split-${USER_NAME}"

if [[ -n "$SUBVOL" ]]; then
  [[ -n "$BTRFS_DEV" ]] || die "--btrfs-subvol requires --btrfs-device"
  echo "==> preparing btrfs subvolume ${SUBVOL} on ${BTRFS_DEV}"
  run mkdir -p /mnt/btrfs-top
  run mount -o subvol=/ "$BTRFS_DEV" /mnt/btrfs-top

  OLD_SUBVOL="${SUBVOL%-home}-local"
  if [[ "$APPLY" -eq 0 ]]; then
    echo "  would check for /mnt/btrfs-top/${OLD_SUBVOL} to rename, else create ${SUBVOL}"
  elif [[ -d "/mnt/btrfs-top/${OLD_SUBVOL}" ]]; then
    # Reuse the existing host-local subvolume rather than copying its contents.
    # It currently holds what used to be mounted at ~/.local, so its share/ and
    # state/ move down one level into .local/. Both operations stay inside the
    # subvolume, so they are renames, not copies -- this matters because the
    # subvolume holds Steam libraries.
    echo "  + reusing ${OLD_SUBVOL} as ${SUBVOL}"
    btrfs subvolume rename "/mnt/btrfs-top/${OLD_SUBVOL}" "/mnt/btrfs-top/${SUBVOL}"
    mkdir -p "/mnt/btrfs-top/${SUBVOL}/.local"
    for d in share state; do
      if [[ -d "/mnt/btrfs-top/${SUBVOL}/${d}" ]]; then
        mv "/mnt/btrfs-top/${SUBVOL}/${d}" "/mnt/btrfs-top/${SUBVOL}/.local/${d}"
      fi
    done
    chown "${USER_NAME}" "/mnt/btrfs-top/${SUBVOL}" "/mnt/btrfs-top/${SUBVOL}/.local"
  else
    echo "  + creating fresh subvolume ${SUBVOL}"
    btrfs subvolume create "/mnt/btrfs-top/${SUBVOL}"
    chown "${USER_NAME}" "/mnt/btrfs-top/${SUBVOL}"
  fi

  run umount /mnt/btrfs-top
  run rmdir /mnt/btrfs-top

  run mkdir -p "$STAGING"
  run mount -o "subvol=${SUBVOL},compress=zstd,noatime,ssd,discard=async" "$BTRFS_DEV" "$STAGING"
else
  echo "==> preparing plain local home directory"
  run mkdir -p "$STAGING"
fi

# ---------------------------------------------------------------------------
# Copy everything that is NOT shared into the local home
# ---------------------------------------------------------------------------

echo
echo "==> copying non-shared content into the local home"

RSYNC_ARGS=(-aHAX --info=stats2)
for p in "${SHARED_PATHS[@]}" "${SHARED_FILES[@]}"; do
  # Leading slash anchors the exclude at the transfer root, so a shared
  # "Documents" does not also exclude "Projects/foo/Documents".
  RSYNC_ARGS+=(--exclude="/${p}")
done
# Never copy the old whole-home Home Manager artifacts: these are the dangling
# /nix/store symlinks that caused the problem in the first place. The rebuild
# regenerates them for this host.
for p in .zshrc .zshenv .p10k.zsh .nix-profile .nix-defexpr; do
  RSYNC_ARGS+=(--exclude="/${p}")
done
if [[ -n "$SUBVOL" ]]; then
  # .local already lives in the reused subvolume; do not overwrite it with the
  # shared root's copy.
  RSYNC_ARGS+=(--exclude="/.local")
fi

if [[ "$APPLY" -eq 1 ]]; then
  rsync "${RSYNC_ARGS[@]}" "${SHARED_HOME}/" "${STAGING}/"
  chown -R "${USER_NAME}" "${STAGING}"
else
  echo "  would run: rsync ${RSYNC_ARGS[*]} ${SHARED_HOME}/ ${STAGING}/"
  echo
  echo "  --- dry-run transfer list (first 40) ---"
  rsync "${RSYNC_ARGS[@]}" --dry-run --itemize-changes \
    "${SHARED_HOME}/" "${STAGING}/" 2>/dev/null | head -40 || true
fi

# ---------------------------------------------------------------------------
# Swap the old symlink for the populated local home
# ---------------------------------------------------------------------------

echo
echo "==> replacing ${LOCAL_HOME}"

if [[ -n "$SUBVOL" ]]; then
  run umount "$STAGING"
  run rmdir "$STAGING"
  run rm -f "$LOCAL_HOME"
  run mkdir -p "$LOCAL_HOME"
  echo "    (the rebuild mounts ${SUBVOL} at ${LOCAL_HOME})"
else
  run rm -f "$LOCAL_HOME"
  run mv "$STAGING" "$LOCAL_HOME"
  run chown "${USER_NAME}" "$LOCAL_HOME"
fi

echo
echo "==> done. Next:"
echo "    sudo nixos-rebuild switch --refresh --flake '${FLAKE}#${HOSTNAME_SHORT}'"
echo
echo "    Nothing under ${SHARED_HOME} was deleted. To roll back, remove"
echo "    ${LOCAL_HOME} and rebuild the previous generation."
