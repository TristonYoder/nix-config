#!/usr/bin/env bash
# Generate OIDC secrets for any service using Pocket ID
# This script encrypts client_id and client_secret from Pocket ID OIDC clients

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}=== Generate OIDC Secrets for Service ===${NC}"
echo ""

# Check if encrypt-secret.sh exists
if [ ! -f "encrypt-secret.sh" ]; then
    echo -e "${RED}Error: encrypt-secret.sh not found in current directory${NC}"
    exit 1
fi

# Make sure encrypt-secret.sh is executable
chmod +x encrypt-secret.sh

echo -e "${YELLOW}Prerequisites:${NC}"
echo "  1. Create OIDC client in Pocket ID (https://id.theyoder.family)"
echo "  2. Set redirect URI: https://<domain>/caddy-security/oauth2/<realm>/authorization-code-callback"
echo "  3. Copy client_id and client_secret from Pocket ID"
echo ""

# Prompt for service name
read -p "Service name (e.g., code-server, kasm, immich): " SERVICE_NAME

if [ -z "$SERVICE_NAME" ]; then
    echo -e "${RED}Error: Service name is required${NC}"
    exit 1
fi

# Prompt for realm (optional, defaults to service name)
read -p "Realm name (default: ${SERVICE_NAME}): " REALM_NAME
if [ -z "$REALM_NAME" ]; then
    REALM_NAME="$SERVICE_NAME"
fi

# Prompt for host (optional, defaults to david)
read -p "Target host (default: david): " TARGET_HOST
if [ -z "$TARGET_HOST" ]; then
    TARGET_HOST="david"
fi

echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  Service:  $SERVICE_NAME"
echo "  Realm:    $REALM_NAME"
echo "  Host:     $TARGET_HOST"
echo ""

# Prompt for client_id and client_secret from Pocket ID
read -p "Client ID from Pocket ID: " CLIENT_ID

if [ -z "$CLIENT_ID" ]; then
    echo -e "${RED}Error: Client ID is required${NC}"
    exit 1
fi

read -sp "Client Secret from Pocket ID: " CLIENT_SECRET
echo ""

if [ -z "$CLIENT_SECRET" ]; then
    echo -e "${RED}Error: Client Secret is required${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Encrypting secrets...${NC}"
echo ""

# Encrypt client_id using encrypt-secret.sh
echo -e "${BLUE}[1/2] Encrypting client ID...${NC}"
./encrypt-secret.sh -n "pocket-id-client-${SERVICE_NAME}-id.age" -h "$TARGET_HOST" -s "$CLIENT_ID"

# Encrypt client_secret using encrypt-secret.sh
echo ""
echo -e "${BLUE}[2/2] Encrypting client secret...${NC}"
./encrypt-secret.sh -n "pocket-id-client-${SERVICE_NAME}-secret.age" -h "$TARGET_HOST" -s "$CLIENT_SECRET"

echo ""
echo -e "${GREEN}=== Secrets Encrypted Successfully! ===${NC}"
echo ""
echo -e "${BLUE}Secrets created:${NC}"
echo "  ✓ pocket-id-client-${SERVICE_NAME}-id.age"
echo "  ✓ pocket-id-client-${SERVICE_NAME}-secret.age"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo -e "${BLUE}1. Update secrets/secrets.nix to include these secrets:${NC}"
echo ""
echo "   # ${SERVICE_NAME} OIDC client"
echo "   \"pocket-id-client-${SERVICE_NAME}-id.age\".publicKeys = ${TARGET_HOST}Keys;"
echo "   \"pocket-id-client-${SERVICE_NAME}-secret.age\".publicKeys = ${TARGET_HOST}Keys;"
echo ""
echo -e "${BLUE}2. Commit the encrypted .age files:${NC}"
echo ""
echo "   git add secrets/pocket-id-client-${SERVICE_NAME}-*.age"
echo "   git commit -m 'feat: Add ${SERVICE_NAME} OIDC secrets'"
echo ""
echo -e "${BLUE}3. Add OIDC configuration to your service module:${NC}"
echo ""
echo "   See modules/README-OIDC.md for implementation guide"
echo ""
echo -e "${BLUE}4. Example service configuration:${NC}"
echo ""
echo "   caddyOIDC = {"
echo "     enable = true;"
echo "     realm = \"${REALM_NAME}\";"
echo "     allowedGroups = [ \"admin\" ];  # Customize as needed"
echo "     clientIdFile = config.age.secrets.pocket-id-client-${SERVICE_NAME}-id.path;"
echo "     clientSecretFile = config.age.secrets.pocket-id-client-${SERVICE_NAME}-secret.path;"
echo "   };"
echo ""
echo -e "${BLUE}5. Pocket ID callback URL (for reference):${NC}"
echo ""
echo "   https://<your-domain>/caddy-security/oauth2/${REALM_NAME}/authorization-code-callback"
echo ""
