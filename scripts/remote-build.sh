#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/remote-build.sh [options] [hostname] [action] [nixos-rebuild flags...]

Build and deploy a host configuration by building on the build host (default: david)
then copying the closure over Tailscale to the target host.

Options:
  --buildHost <host>   Build host reachable over Tailscale (default: david)
  --targetUser <user>  SSH user for target host (default: root)
  --flake <path>       Flake path (default: .)
  -h, --help           Show this help

Arguments:
  hostname  NixOS host in the flake (defaults to current hostname)
  action    nixos-rebuild action (default: switch)
            switch | boot | test | build | dry-run
  flags     Additional nixos-rebuild flags (e.g. --upgrade, --show-trace)

Environment:
  BUILD_HOST    Build host reachable over Tailscale (default: david)
  TARGET_USER   SSH user for target host (default: root)
  FLAKE_REF     Flake path (default: .)

Examples:
  scripts/remote-build.sh tristons-nixbook
  scripts/remote-build.sh --buildHost david tristons-desk test
  BUILD_HOST=david scripts/remote-build.sh tristons-desk test
  TARGET_USER=triston scripts/remote-build.sh pits switch
  scripts/remote-build.sh tristons-desk switch --upgrade --show-trace
USAGE
}

BUILD_HOST="${BUILD_HOST:-david}"
TARGET_USER="${TARGET_USER:-root}"
FLAKE_REF="${FLAKE_REF:-.}"

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --buildHost)
      BUILD_HOST="$2"
      shift 2
      ;;
    --targetUser)
      TARGET_USER="$2"
      shift 2
      ;;
    --flake)
      FLAKE_REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]}"

DEFAULT_HOST="$(hostname -s 2>/dev/null || hostname)"
HOST="$DEFAULT_HOST"
ACTION="switch"
PASSTHROUGH=()

if [[ "$#" -gt 0 ]]; then
  case "$1" in
    switch|boot|test|build|dry-run)
      ACTION="$1"
      if [[ "$#" -gt 1 ]]; then
        PASSTHROUGH=("${@:2}")
      fi
      ;;
    *)
      HOST="$1"
      if [[ "$#" -gt 1 ]]; then
        case "$2" in
          switch|boot|test|build|dry-run)
            ACTION="$2"
            if [[ "$#" -gt 2 ]]; then
              PASSTHROUGH=("${@:3}")
            fi
            ;;
          *)
            ACTION="switch"
            PASSTHROUGH=("${@:2}")
            ;;
        esac
      fi
      ;;
  esac
fi

case "${ACTION}" in
  switch|boot|test|build|dry-run) ;;
  *)
    echo "Unknown action: ${ACTION}" >&2
    usage
    exit 1
    ;;
esac

TARGET_HOST="${TARGET_USER}@${HOST}"

if [[ "${ACTION}" == "build" || "${ACTION}" == "dry-run" ]]; then
  nixos-rebuild "${ACTION}" "${PASSTHROUGH[@]}" --flake "${FLAKE_REF}#${HOST}" --build-host "${BUILD_HOST}"
  exit 0
fi

nixos-rebuild "${ACTION}" \
  "${PASSTHROUGH[@]}" \
  --flake "${FLAKE_REF}#${HOST}" \
  --build-host "${BUILD_HOST}" \
  --target-host "${TARGET_HOST}" \
  --use-remote-sudo
