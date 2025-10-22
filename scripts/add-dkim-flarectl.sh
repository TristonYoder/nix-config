#!/usr/bin/env bash
# Add DKIM record using flarectl

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}Error: DKIM public key required${NC}"
    echo ""
    echo "Usage: $0 '<dkim-public-key>'"
    echo ""
    echo "To get your DKIM key:"
    echo "  1. Visit https://mailadmin.7andco.studio"
    echo "  2. Go to Settings → DKIM"
    echo "  3. Copy the public key (long base64 string)"
    exit 1
fi

DKIM_KEY="$1"
DKIM_VALUE="v=DKIM1; k=rsa; p=$DKIM_KEY"

if [ -z "$CLOUDFLARE_API_TOKEN" ] && [ -z "$CLOUDFLARE_API_KEY" ]; then
    echo -e "${YELLOW}Please set CLOUDFLARE_API_TOKEN${NC}"
    exit 1
fi

echo -e "${BLUE}Adding DKIM record to 7andco.dev...${NC}"

flarectl dns create \
    --zone "7andco.dev" \
    --name "default._domainkey" \
    --type "TXT" \
    --content "$DKIM_VALUE" \
    2>&1 | grep -v "error code: 81057" || true

echo ""
echo -e "${GREEN}✓ DKIM record created!${NC}"
echo ""
echo "Verify with:"
echo "  dig TXT default._domainkey.7andco.dev"

