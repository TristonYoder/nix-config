#!/usr/bin/env bash
# Regenerate Stalwart Mail Server secrets with custom passwords
# Uses SSH public keys (not age keys) for proper agenix compatibility
# Fixes newline issue by using echo -n

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Regenerate Stalwart Mail Secrets ===${NC}"
echo ""

# SSH public keys (from actual servers)
DAVID_SSH="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFenzKCacIrb/vKK33VcPnQq2QUSX6mhxvBVWyZqG4x2 root@nixos"
PITS_SSH="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ9FEilz6t5lcw3OZLqvjJur1vmzDAV39MnL5c/ozDV+ root@nixos"
ADMIN_SSH="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl3RK/gkxLiFzZOAf5Y29hzgWX+vGUE42iPz7RAm9KH agenix-secrets@david-nixos"

# Function to encrypt a secret (NO NEWLINE, using SSH keys with -R flag)
encrypt_secret() {
    local password="$1"
    local output_file="$2"
    
    echo -e "${BLUE}Creating: $output_file${NC}"
    echo -n "$password" | age -R <(echo "$DAVID_SSH") -R <(echo "$PITS_SSH") -R <(echo "$ADMIN_SSH") -o "$output_file"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Created $output_file (no trailing newline)${NC}"
    else
        echo -e "${YELLOW}✗ Failed to create $output_file${NC}"
        exit 1
    fi
}

# Get passwords from user
echo -e "${YELLOW}Enter passwords (or press Enter to use defaults):${NC}"
echo ""

read -p "Postmaster password (postmaster@7andco.dev): " POSTMASTER_PW
if [ -z "$POSTMASTER_PW" ]; then
    POSTMASTER_PW="StrongPostmasterPassword2024!"
fi

read -p "Admin mail password (admin@7andco.dev): " ADMIN_MAIL_PW
if [ -z "$ADMIN_MAIL_PW" ]; then
    ADMIN_MAIL_PW="StrongAdminPassword2024!"
fi

read -p "Admin web password (https://mailadmin.7andco.dev): " ADMIN_WEB_PW
if [ -z "$ADMIN_WEB_PW" ]; then
    ADMIN_WEB_PW="StrongAdminWebPassword2024!"
fi

echo ""
echo -e "${BLUE}Creating encrypted secrets using SSH public keys...${NC}"
echo ""

# Remove old secrets
rm -f stalwart-postmaster-password.age
rm -f stalwart-admin-password.age
rm -f stalwart-admin-web-password.age

# Create new secrets (echo -n = no newline, -R = SSH keys)
encrypt_secret "$POSTMASTER_PW" "stalwart-postmaster-password.age"
encrypt_secret "$ADMIN_MAIL_PW" "stalwart-admin-password.age"
encrypt_secret "$ADMIN_WEB_PW" "stalwart-admin-web-password.age"

echo ""
echo -e "${GREEN}=== Secrets Created Successfully! ===${NC}"
echo ""
echo "Next steps:"
echo "  cd .."
echo "  git add secrets/stalwart-*.age"
echo "  git commit -m 'Update Stalwart secrets'"
echo "  git push"
echo ""
echo -e "${BLUE}Your passwords:${NC}"
echo "Admin web: $ADMIN_WEB_PW"
echo "Postmaster: $POSTMASTER_PW"
echo "Admin mail: $ADMIN_MAIL_PW"
