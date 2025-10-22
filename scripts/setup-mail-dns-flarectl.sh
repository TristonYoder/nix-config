#!/usr/bin/env bash
# Setup DNS records for Stalwart Mail Server using flarectl
# Much simpler than using curl/API directly!

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
PITS_IPV4="66.135.18.197"
PITS_IPV6="2001:19f0:c:d11:8e9e:d06c:8518:5829"

echo -e "${BLUE}=== Stalwart Mail Server DNS Setup (using flarectl) ===${NC}"
echo ""

# Check for API token/email
if [ -z "$CLOUDFLARE_API_TOKEN" ] && [ -z "$CLOUDFLARE_API_KEY" ]; then
    echo -e "${YELLOW}Please set CLOUDFLARE_API_TOKEN environment variable${NC}"
    echo "Get it from: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    echo "Usage:"
    echo "  export CLOUDFLARE_API_TOKEN='your-token-here'"
    echo "  $0"
    exit 1
fi

# Function to create DNS record with flarectl
create_dns() {
    local zone=$1
    local type=$2
    local name=$3
    local content=$4
    local priority=${5:-}
    
    echo -e "${BLUE}Creating $type record: $name${NC}"
    
    if [ "$type" = "MX" ]; then
        flarectl dns create --zone "$zone" --name "$name" --type "$type" --content "$content" --priority "$priority" 2>&1 | grep -v "error code: 81057" || true
    else
        flarectl dns create --zone "$zone" --name "$name" --type "$type" --content "$content" 2>&1 | grep -v "error code: 81057" || true
    fi
    
    if [ $? -eq 0 ] || echo "$output" | grep -q "81057"; then
        echo -e "${GREEN}✓ Record created or already exists: $name${NC}"
    fi
}

echo -e "${BLUE}=== Creating DNS Records for 7andco.dev ===${NC}"

# MX Record
create_dns "7andco.dev" "MX" "7andco.dev" "mail.7andco.dev" "10"

# A/AAAA Records for mail subdomain
create_dns "7andco.dev" "A" "mail" "$PITS_IPV4"
create_dns "7andco.dev" "AAAA" "mail" "$PITS_IPV6"

# SPF Record
create_dns "7andco.dev" "TXT" "7andco.dev" "v=spf1 mx ~all"

# DMARC Record
create_dns "7andco.dev" "TXT" "_dmarc" "v=DMARC1; p=quarantine; rua=mailto:postmaster@7andco.dev"

# MTA-STS Record  
create_dns "7andco.dev" "TXT" "_mta-sts" "v=STSv1; id=20251022"

echo ""
echo -e "${BLUE}=== Creating DNS Records for 7andco.studio ===${NC}"

# A/AAAA Records for webmail
create_dns "7andco.studio" "A" "mail" "$PITS_IPV4"
create_dns "7andco.studio" "AAAA" "mail" "$PITS_IPV6"

# A/AAAA Records for admin interface
create_dns "7andco.studio" "A" "mailadmin" "$PITS_IPV4"
create_dns "7andco.studio" "AAAA" "mailadmin" "$PITS_IPV6"

echo ""
echo -e "${GREEN}=== DNS Records Created! ===${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. ${BLUE}Wait 5-10 minutes${NC} for DNS propagation"
echo ""
echo "2. ${BLUE}Verify DNS records:${NC}"
echo "   dig MX 7andco.dev"
echo "   dig A mail.7andco.dev"
echo "   dig TXT 7andco.dev"
echo ""
echo "3. ${BLUE}Deploy Stalwart:${NC}"
echo "   nixos-rebuild switch --flake .#pits --target-host pits"
echo ""
echo "4. ${BLUE}Add DKIM record${NC} (after deployment):"
echo "   • Login: https://mailadmin.7andco.studio"
echo "   • Get public key from Settings → DKIM"
echo "   • Run: ./scripts/add-dkim-flarectl.sh '<public-key>'"
echo ""
echo "5. ${BLUE}Configure reverse DNS${NC} at your VPS provider:"
echo "   66.135.18.197 → mail.7andco.dev"
echo ""
echo -e "${GREEN}Done! 🎉${NC}"

