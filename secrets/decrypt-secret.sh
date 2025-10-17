#!/usr/bin/env bash

# Secrets Decryption Helper Script
# Decrypts agenix secrets for viewing/editing using your admin key

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default admin key location
ADMIN_KEY_FILE="$HOME/.ssh/agenix"

# Usage information
usage() {
    cat << EOF
${BLUE}Usage:${NC} $0 [OPTIONS] SECRET_FILE

${BLUE}Description:${NC}
  Decrypts agenix secrets for viewing using your admin key.

${BLUE}Options:${NC}
  -i, --identity FILE     Path to admin SSH key (default: ~/.ssh/agenix)
  -o, --output FILE       Write decrypted content to file instead of stdout
  --help                  Show this help message

${BLUE}Examples:${NC}
  # View secret
  $0 cloudflare-api-token.age

  # Decrypt to file
  $0 -o /tmp/secret.txt cloudflare-api-token.age

  # Use different identity key
  $0 -i ~/.ssh/id_ed25519 my-secret.age

${BLUE}Note:${NC}
  This requires your admin private key (~/.ssh/agenix by default).
  You must be listed as a recipient in secrets.nix to decrypt.

EOF
    exit 0
}

# Parse command line arguments
OUTPUT_FILE=""
SECRET_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--identity)
            ADMIN_KEY_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            if [ -z "$SECRET_FILE" ]; then
                SECRET_FILE="$1"
            else
                echo -e "${RED}Error: Unknown option $1${NC}"
                usage
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$SECRET_FILE" ]; then
    echo -e "${RED}Error: Secret file is required${NC}"
    usage
fi

if [ ! -f "$SECRET_FILE" ]; then
    echo -e "${RED}Error: Secret file not found: $SECRET_FILE${NC}"
    exit 1
fi

if [ ! -f "$ADMIN_KEY_FILE" ]; then
    echo -e "${RED}Error: Admin key not found: $ADMIN_KEY_FILE${NC}"
    echo -e "${YELLOW}Hint: Create one with:${NC}"
    echo "  ssh-keygen -t ed25519 -f ~/.ssh/agenix -N \"\""
    echo "  cat ~/.ssh/agenix.pub | nix-shell -p ssh-to-age --run \"ssh-to-age\""
    echo "  # Add the output to adminKeys in secrets/secrets.nix"
    exit 1
fi

# Decrypt the secret
# Note: age can read SSH private keys directly, no conversion needed
echo -e "${BLUE}Decrypting $SECRET_FILE...${NC}"
if [ -n "$OUTPUT_FILE" ]; then
    if nix-shell -p age --run "age --decrypt -i \"$ADMIN_KEY_FILE\" \"$SECRET_FILE\"" > "$OUTPUT_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully decrypted to: $OUTPUT_FILE${NC}"
    else
        echo -e "${RED}✗ Decryption failed${NC}"
        echo -e "${YELLOW}Possible reasons:${NC}"
        echo "  - Your admin key is not listed as a recipient"
        echo "  - The secret was encrypted with different keys"
        echo "  - The secret file is corrupted"
        exit 1
    fi
else
    if ! nix-shell -p age --run "age --decrypt -i \"$ADMIN_KEY_FILE\" \"$SECRET_FILE\"" 2>/dev/null; then
        echo -e "${RED}✗ Decryption failed${NC}"
        echo -e "${YELLOW}Possible reasons:${NC}"
        echo "  - Your admin key is not listed as a recipient"
        echo "  - The secret was encrypted with different keys"
        echo "  - The secret file is corrupted"
        exit 1
    fi
fi

