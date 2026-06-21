#!/usr/bin/env bash

# Fetch SSH host public keys from managed hosts and store in secrets/keys/
# Run this whenever a host is added or reprovisioned (new install = new host key).
# Public keys are not secrets — safe to commit.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

KEYS_DIR="$(cd "$(dirname "$0")" && pwd)/keys"
mkdir -p "$KEYS_DIR"

# Known hosts: name=ssh-target pairs
declare -A HOSTS=(
    [david]="tristonyoder@david"
    [pits]="tristonyoder@pits"
    [tristons-workstation]="tristonyoder@tristons-workstation"
    [tristons-nixbook]="tristonyoder@tristons-nixbook"
    [tristons-nixbook-pro]="tristonyoder@tristons-nixbook-pro"
    [tyoder-mbp]="tristonyoder@tyoder-mbp"
)

usage() {
    cat << EOF
${BLUE}Usage:${NC} $0 [host ...]

Fetches /etc/ssh/ssh_host_ed25519_key.pub from each host and writes it to
secrets/keys/<host>.pub. Skips unreachable hosts with a warning.

${BLUE}Known hosts:${NC}
$(for h in "${!HOSTS[@]}"; do echo "  $h  →  ${HOSTS[$h]}"; done | sort)

${BLUE}Examples:${NC}
  $0                      # refresh all known hosts
  $0 david pits           # refresh specific hosts
  $0 my-new-host          # fetch unknown host (prompts for SSH target)

EOF
    exit 0
}

[[ "$1" == "--help" || "$1" == "-h" ]] && usage

# Determine which hosts to fetch
if [ $# -eq 0 ]; then
    TARGETS=("${!HOSTS[@]}")
else
    TARGETS=("$@")
fi

fetch_key() {
    local name="$1" target="$2"
    local outfile="$KEYS_DIR/${name}.pub"

    printf "  %-30s" "$name"
    local key
    if key=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$target" \
              "cat /etc/ssh/ssh_host_ed25519_key.pub" 2>/dev/null); then
        echo "$key" > "$outfile"
        echo -e "${GREEN}✓${NC}  $outfile"
    else
        echo -e "${YELLOW}skipped (unreachable)${NC}"
    fi
}

echo -e "${BLUE}Fetching SSH host keys into $KEYS_DIR${NC}"
echo ""

for name in "${TARGETS[@]}"; do
    if [ -n "${HOSTS[$name]}" ]; then
        fetch_key "$name" "${HOSTS[$name]}"
    else
        # Unknown host — ask for SSH target
        echo -e "${YELLOW}Unknown host '$name'. Enter SSH target (user@host):${NC} "
        read -r target
        if [ -n "$target" ]; then
            fetch_key "$name" "$target"
        else
            echo -e "${RED}  skipped (no target provided)${NC}"
        fi
    fi
done

echo ""
echo -e "${BLUE}Current keys:${NC}"
for f in "$KEYS_DIR"/*.pub; do
    printf "  %-35s  %s\n" "$(basename "$f")" "$(cut -d' ' -f1-2 "$f")"
done

echo ""
echo -e "${YELLOW}If any keys changed, re-encrypt affected secrets:${NC}"
echo "  ./encrypt-secret.sh -n <secret>.age -f <(./decrypt-secret.sh <secret>.age)"
