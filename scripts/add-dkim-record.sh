#!/usr/bin/env bash
# Add DKIM record for Stalwart Mail Server
# Run this AFTER deploying and getting the public key from the admin panel

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
    echo "  2. Login with admin credentials"
    echo "  3. Go to Settings → DKIM"
    echo "  4. Copy the public key (long base64 string)"
    echo ""
    exit 1
fi

DKIM_KEY="$1"
CF_API="https://api.cloudflare.com/client/v4"

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo -e "${YELLOW}Please set CLOUDFLARE_API_TOKEN environment variable${NC}"
    exit 1
fi

cf_api() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ -n "$data" ]; then
        curl -s -X "$method" "$CF_API$endpoint" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$data"
    else
        curl -s -X "$method" "$CF_API$endpoint" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json"
    fi
}

echo -e "${BLUE}Getting zone ID for 7andco.dev...${NC}"
response=$(cf_api "GET" "/zones?name=7andco.dev")
ZONE_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$ZONE_ID" ]; then
    echo -e "${RED}Error: Could not find zone${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Zone ID: $ZONE_ID${NC}"
echo ""

DKIM_VALUE="v=DKIM1; k=rsa; p=$DKIM_KEY"

echo -e "${BLUE}Creating DKIM record...${NC}"
data="{\"type\":\"TXT\",\"name\":\"default._domainkey.7andco.dev\",\"content\":\"$DKIM_VALUE\",\"ttl\":3600,\"proxied\":false}"

response=$(cf_api "POST" "/zones/$ZONE_ID/dns_records" "$data")

if echo "$response" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ DKIM record created successfully!${NC}"
    echo ""
    echo "Verify with:"
    echo "  dig TXT default._domainkey.7andco.dev"
else
    echo -e "${YELLOW}Response:${NC}"
    echo "$response"
fi

