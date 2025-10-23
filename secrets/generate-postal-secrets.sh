#!/usr/bin/env bash
# Generate Postal secrets using the proper encryption script
# This script generates all necessary secrets and encrypts them using encrypt-secret.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}=== Generate Postal Mail Server Secrets ===${NC}"
echo ""

# Check if encrypt-secret.sh exists
if [ ! -f "encrypt-secret.sh" ]; then
    echo -e "${RED}Error: encrypt-secret.sh not found in current directory${NC}"
    exit 1
fi

# Make sure encrypt-secret.sh is executable
chmod +x encrypt-secret.sh

echo -e "${BLUE}This will generate the following secrets:${NC}"
echo "  1. postal-db-password.age       - MariaDB root password"
echo "  2. postal-rails-secret.age      - Rails secret key base (128 hex chars)"
echo "  3. postal-signing-key.age       - RSA signing key (PEM format)"
echo "  4. postal-admin-email.age       - Admin user email"
echo "  5. postal-admin-password.age    - Admin user password"
echo ""

read -p "Continue? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Generating secrets...${NC}"
echo ""

# 1. Generate database password
echo -e "${BLUE}[1/5] Generating MariaDB password...${NC}"
DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
./encrypt-secret.sh -n postal-db-password.age -h pits -s "$DB_PASSWORD"

# 2. Generate Rails secret key
echo ""
echo -e "${BLUE}[2/5] Generating Rails secret key...${NC}"
RAILS_SECRET=$(openssl rand -hex 128 | tr -d '\n')
./encrypt-secret.sh -n postal-rails-secret.age -h pits -s "$RAILS_SECRET"

# 3. Generate signing key (RSA private key in PEM format)
echo ""
echo -e "${BLUE}[3/5] Generating RSA signing key...${NC}"
SIGNING_KEY=$(openssl genrsa 1024 2>/dev/null)
./encrypt-secret.sh -n postal-signing-key.age -h pits -s "$SIGNING_KEY"

# 4. Admin email
echo ""
echo -e "${BLUE}[4/5] Setting admin email...${NC}"
read -p "Enter admin email (default: admin@7andco.dev): " ADMIN_EMAIL
if [ -z "$ADMIN_EMAIL" ]; then
    ADMIN_EMAIL="admin@7andco.dev"
fi
./encrypt-secret.sh -n postal-admin-email.age -h pits -s "$ADMIN_EMAIL"

# 5. Generate admin password
echo ""
echo -e "${BLUE}[5/5] Generating admin password...${NC}"
read -p "Enter admin password (or press Enter to generate): " ADMIN_PASSWORD
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
    echo -e "${GREEN}Generated password: ${YELLOW}$ADMIN_PASSWORD${NC}"
fi
./encrypt-secret.sh -n postal-admin-password.age -h pits -s "$ADMIN_PASSWORD"

echo ""
echo -e "${GREEN}=== All Postal Secrets Generated Successfully! ===${NC}"
echo ""
echo -e "${BLUE}Secrets created:${NC}"
echo "  ✓ postal-db-password.age"
echo "  ✓ postal-rails-secret.age"
echo "  ✓ postal-signing-key.age"
echo "  ✓ postal-admin-email.age"
echo "  ✓ postal-admin-password.age"
echo ""
echo -e "${YELLOW}IMPORTANT: Save these credentials securely!${NC}"
echo ""
echo -e "${BLUE}Admin Credentials:${NC}"
echo "  Email:    $ADMIN_EMAIL"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo -e "${BLUE}To retrieve the password later:${NC}"
echo "  age -d -i ~/.ssh/agenix postal-admin-password.age"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Update secrets/secrets.nix to include these secrets"
echo "  2. Commit the encrypted .age files:"
echo "     git add secrets/postal-*.age"
echo "     git commit -m 'Add Postal mail server secrets'"
echo "  3. Deploy to PITS:"
echo "     nixos-rebuild switch --flake .#pits"
echo ""

