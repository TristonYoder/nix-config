#!/usr/bin/env bash
# Setup DNS records for Stalwart Mail Server
# All subdomains under 7andco.dev
# Uses Cloudflare API

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PITS_IPV4="66.135.18.197"
PITS_IPV6="2001:19f0:c:d11:8e9e:d06c:8518:5829"
DOMAIN="7andco.dev"

# Cloudflare API endpoint
CF_API="https://api.cloudflare.com/client/v4"

echo -e "${BLUE}=== Stalwart Mail Server DNS Setup ===${NC}"
echo ""

# Check for API token
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo -e "${YELLOW}Please set CLOUDFLARE_API_TOKEN environment variable${NC}"
    echo "You can find it at: https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    echo "Usage:"
    echo "  export CLOUDFLARE_API_TOKEN='your-token-here'"
    echo "  ./setup-mail-dns.sh"
    exit 1
fi

# Function to make Cloudflare API calls
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

# Function to get zone ID
get_zone_id() {
    local domain=$1
    echo -e "${BLUE}Getting zone ID for $domain...${NC}"
    
    local response=$(cf_api "GET" "/zones?name=$domain")
    local zone_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$zone_id" ]; then
        echo -e "${RED}Error: Could not find zone for $domain${NC}"
        echo "Response: $response"
        return 1
    fi
    
    echo "$zone_id"
}

# Function to create DNS record
create_dns_record() {
    local zone_id=$1
    local type=$2
    local name=$3
    local content=$4
    local priority=${5:-}
    local ttl=${6:-3600}
    
    echo -e "${BLUE}Creating $type record: $name${NC}"
    
    local data="{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":$ttl,\"proxied\":false"
    
    if [ -n "$priority" ]; then
        data="$data,\"priority\":$priority"
    fi
    
    data="$data}"
    
    local response=$(cf_api "POST" "/zones/$zone_id/dns_records" "$data")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "${GREEN}✓ Created $type record: $name${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ May already exist or error: $name${NC}"
        echo "Response: $response" | head -5
        return 0  # Don't fail if record exists
    fi
}

# Get zone IDs
echo -e "${BLUE}=== Step 1: Getting Zone ID ===${NC}"
ZONE_7ANDCO_DEV=$(get_zone_id "7andco.dev")

echo -e "${GREEN}✓ Zone ID for 7andco.dev: $ZONE_7ANDCO_DEV${NC}"
echo ""

# Create DNS records for 7andco.dev
echo -e "${BLUE}=== Step 2: Creating DNS Records for $DOMAIN ===${NC}"

# MX Record
create_dns_record "$ZONE_7ANDCO_DEV" "MX" "$DOMAIN" "mail.$DOMAIN" "10"

# A/AAAA Records for mail subdomain
create_dns_record "$ZONE_7ANDCO_DEV" "A" "mail" "$PITS_IPV4"
create_dns_record "$ZONE_7ANDCO_DEV" "AAAA" "mail" "$PITS_IPV6"

# A/AAAA Records for webmail subdomain
create_dns_record "$ZONE_7ANDCO_DEV" "A" "webmail" "$PITS_IPV4"
create_dns_record "$ZONE_7ANDCO_DEV" "AAAA" "webmail" "$PITS_IPV6"

# A/AAAA Records for admin subdomain
create_dns_record "$ZONE_7ANDCO_DEV" "A" "mailadmin" "$PITS_IPV4"
create_dns_record "$ZONE_7ANDCO_DEV" "AAAA" "mailadmin" "$PITS_IPV6"

# SPF Record
create_dns_record "$ZONE_7ANDCO_DEV" "TXT" "$DOMAIN" "v=spf1 mx ~all"

# DMARC Record
create_dns_record "$ZONE_7ANDCO_DEV" "TXT" "_dmarc" "v=DMARC1; p=quarantine; rua=mailto:postmaster@$DOMAIN"

# MTA-STS Record
create_dns_record "$ZONE_7ANDCO_DEV" "TXT" "_mta-sts" "v=STSv1; id=20251022"

echo ""
echo -e "${GREEN}=== DNS Records Created! ===${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. ${BLUE}Deploy Stalwart:${NC}"
echo "   nixos-rebuild switch --flake .#pits --target-host pits"
echo ""
echo "2. ${BLUE}Access Admin Panel:${NC}"
echo "   https://mailadmin.7andco.dev"
echo ""
echo "3. ${BLUE}Add DKIM${NC} (from admin panel):"
echo "   ./scripts/add-dkim-record.sh '<public-key>'"
echo ""
echo "4. ${BLUE}Reverse DNS${NC} (at VPS provider):"
echo "   66.135.18.197 → mail.7andco.dev"
echo ""
echo "5. ${BLUE}Verify DNS${NC} (wait 5-10 min):"
echo "   dig MX $DOMAIN"
echo "   dig A mail.$DOMAIN"
echo ""
echo -e "${GREEN}Done! 🎉${NC}"

