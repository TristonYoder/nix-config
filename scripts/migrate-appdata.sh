#!/usr/bin/env bash
# migrate-appdata.sh
# Migrates service data from /data/docker-appdata to /data/appData
#
# Phases:
#   phase1  — Live sync #1: initial copy while services run. Check dirs and sizes.
#   phase2  — Live sync #2: catch-up sync to minimize final downtime.
#   switch  — Stop services, final sync, nixos-rebuild switch.
#   rollback— Rollback to previous NixOS generation (old paths, data untouched).
#
# Usage: sudo ./scripts/migrate-appdata.sh <phase1|phase2|switch|rollback>

set -euo pipefail

OLD_BASE="/data/docker-appdata"
NEW_BASE="/data/appData"
FLAKE_DIR="/home/tristonyoder/Projects/nix-config"

# -----------------------------------------------------------------------------
# Colours
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
info() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# -----------------------------------------------------------------------------
# Mappings: "source_subdir:dest_subdir"
# source is relative to OLD_BASE, dest is relative to NEW_BASE
# -----------------------------------------------------------------------------
MAPPINGS=(
  "babybuddy:babyBuddy"
  "companion:companion"
  "immich:immich"
  "kasm:kasm"
  "pixelfed:pixelfed"
  "postgres:postgres"
  "romm:romm"
  "stalwart:stalwartMail"
  "syncthing:syncthing"
  "tandoor:tandoor"
  "vaultwarden:vaultwarden"
)

# Native NixOS services (non-Docker) that must be stopped before switch
NATIVE_SERVICES=(
  "postgresql"
  "syncthing"
  "vaultwarden"
  "immich-server"
  "stalwart-mail"
)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
check_root() {
  [[ $EUID -eq 0 ]] || die "Run as root (sudo)."
}

check_dirs() {
  info "=== Source directory inventory ==="
  local missing=0
  for mapping in "${MAPPINGS[@]}"; do
    local src="${OLD_BASE}/${mapping%%:*}"
    if [[ -d "$src" ]]; then
      local size; size=$(du -sh "$src" 2>/dev/null | cut -f1)
      log "  ✓  $(printf '%-35s' "$src")  ${size}"
    else
      warn "  ✗  $src  (not found — will skip)"
      ((missing++)) || true
    fi
  done
  echo
  [[ $missing -gt 0 ]] && warn "$missing source dir(s) not found — they will be skipped."
}

do_rsync() {
  local extra_flags="${1:-}"
  local errors=0

  for mapping in "${MAPPINGS[@]}"; do
    local src="${OLD_BASE}/${mapping%%:*}"
    local dst="${NEW_BASE}/${mapping##*:}"

    if [[ ! -d "$src" ]]; then
      warn "Skipping $src (not found)"
      continue
    fi

    log "rsync  $src  →  $dst"
    mkdir -p "$dst"
    # shellcheck disable=SC2086
    rsync -a --delete --info=progress2 ${extra_flags} "$src/" "$dst/" || {
      err "rsync failed: $src → $dst"
      ((errors++)) || true
    }
  done

  return $errors
}

stop_services() {
  log "Stopping Docker (stops all containers)..."
  systemctl stop docker || warn "docker stop had non-zero exit"

  log "Stopping native NixOS services..."
  for svc in "${NATIVE_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      log "  stopping $svc"
      systemctl stop "$svc" || warn "$svc stop had non-zero exit"
    else
      info "  $svc already stopped — skipping"
    fi
  done
}

start_services() {
  log "Starting native NixOS services..."
  for svc in "${NATIVE_SERVICES[@]}"; do
    log "  starting $svc"
    systemctl start "$svc" || warn "$svc start had non-zero exit"
  done

  log "Starting Docker..."
  systemctl start docker || warn "docker start had non-zero exit"
}

# -----------------------------------------------------------------------------
# Phases
# -----------------------------------------------------------------------------
phase1() {
  check_root
  log "================================================================"
  log "  PHASE 1 — Live sync #1 (services remain running)"
  log "================================================================"
  check_dirs
  log "Starting initial rsync. This may take a while for large datasets."
  echo
  do_rsync
  echo
  log "Phase 1 complete."
  info "Review /data/appData contents before proceeding to phase2."
  info "When ready:  sudo ./scripts/migrate-appdata.sh phase2"
}

phase2() {
  check_root
  log "================================================================"
  log "  PHASE 2 — Live sync #2 catch-up (services remain running)"
  log "================================================================"
  log "Re-syncing to pick up changes written since phase1..."
  echo
  do_rsync
  echo
  log "Phase 2 complete."
  info "When ready to cut over:  sudo ./scripts/migrate-appdata.sh switch"
}

switch_phase() {
  check_root
  log "================================================================"
  log "  PHASE 3 — Stop / Final sync / Switch"
  log "================================================================"
  warn "This will briefly stop all services. Press Ctrl-C within 5s to abort."
  sleep 5

  stop_services
  echo

  log "Running final rsync..."
  do_rsync
  echo

  log "Switching NixOS configuration to feat/appdata-module..."
  nixos-rebuild switch --flake "${FLAKE_DIR}#david"
  echo

  start_services
  echo

  log "================================================================"
  log "  Switch complete."
  log "  Old data remains intact at ${OLD_BASE} — verify services"
  log "  thoroughly before removing it."
  log "================================================================"
  info "If anything is wrong:  sudo ./scripts/migrate-appdata.sh rollback"
}

rollback() {
  check_root
  log "================================================================"
  log "  ROLLBACK — Reverting to previous NixOS generation"
  log "================================================================"
  warn "Stopping services before rollback..."
  stop_services
  echo

  log "Rolling back to previous generation (restores old dataDir paths)..."
  nixos-rebuild switch --rollback
  echo

  start_services
  echo

  log "================================================================"
  log "  Rollback complete."
  log "  Services are pointing back to ${OLD_BASE}."
  log "  Data at ${NEW_BASE} is untouched."
  log "================================================================"
}

# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------
case "${1:-}" in
  phase1)   phase1 ;;
  phase2)   phase2 ;;
  switch)   switch_phase ;;
  rollback) rollback ;;
  *)
    echo "Usage: sudo $0 <phase1|phase2|switch|rollback>"
    echo
    echo "  phase1   Initial live sync — verify dirs and sizes, copy data"
    echo "  phase2   Catch-up live sync — minimise downtime at switch time"
    echo "  switch   Stop services, final sync, nixos-rebuild switch"
    echo "  rollback Revert to previous NixOS generation, restart services"
    exit 1
    ;;
esac
