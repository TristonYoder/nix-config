#!/usr/bin/env bash

# Secrets Encryption Helper Script
# Encrypts secrets for agenix using the correct method (SSH public keys with -R flag)
# 
# CRITICAL: Must use SSH public keys (ssh-ed25519), NOT age X25519 keys!
# Agenix requires secrets encrypted with SSH keys so servers can decrypt using
# their SSH host private keys (/etc/ssh/ssh_host_ed25519_key)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# SSH public keys for encryption (NOT age keys - agenix needs SSH format)
# These are fetched dynamically from the servers
DAVID_HOST="david"
PITS_HOST="pits"
ADMIN_SSH_KEY="$HOME/.ssh/agenix.pub"

# Usage information
usage() {
    cat << EOF
${BLUE}Usage:${NC} $0 [OPTIONS]

${BLUE}Description:${NC}
  Encrypts secrets for agenix with proper SSH public key recipients.
  
  ${YELLOW}IMPORTANT:${NC} This script uses SSH public keys (-R flag) for encryption.
  The encrypted file MUST have "-> ssh-ed25519" recipients, NOT "-> X25519".
  This is required for agenix to decrypt using server SSH host keys.

${BLUE}Options:${NC}
  -n, --name NAME         Output filename (e.g., my-secret.age)
  -h, --hosts HOSTS       Comma-separated host list: david,pits,all (default: all)
  -e, --env-format        Use environment variable format (KEY=value)
  -f, --file FILE         Read secret from file instead of stdin
  -s, --secret SECRET     Provide secret directly as argument
  -v, --verify FILE       Verify an existing .age file has correct format
  --help                  Show this help message

${BLUE}Examples:${NC}
  # Interactive prompt (recommended)
  $0 -n cloudflare-token.age -e

  # From command line
  $0 -n api-key.age -s "my-secret-value"

  # From file
  $0 -n db-password.age -f /path/to/password.txt

  # Environment variable format
  $0 -n token.age -e -s "API_TOKEN=abc123"

  # Only for specific hosts
  $0 -n david-only.age -h david -s "secret"
  
  # Verify existing secret has correct format
  $0 -v cloudflare-api-token.age

${BLUE}Recipients:${NC}
  david: SSH host key for david server
  pits:  SSH host key for pits server
  admin: Admin SSH key for local secret management
  all:   All of the above (default)

${BLUE}Troubleshooting:${NC}
  If you get "no identity matched any of the recipients" during nixos-rebuild:
  1. Verify the secret has ssh-ed25519 recipients: head yourfile.age
  2. Run: $0 -v yourfile.age
  3. If it shows X25519, re-encrypt with this script

EOF
    exit 0
}

# Verify an existing .age file has the correct format
verify_secret() {
    local FILE="$1"
    
    if [ ! -f "$FILE" ]; then
        echo -e "${RED}✗ File not found: $FILE${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Verifying: $FILE${NC}"
    echo ""
    
    # Check for age header
    if ! head -1 "$FILE" | grep -q "age-encryption.org/v1"; then
        echo -e "${RED}✗ Invalid age file (missing header)${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Valid age file format${NC}"
    
    # Check for SSH recipients
    if grep -q "^-> ssh-ed25519" "$FILE"; then
        local COUNT=$(grep -c "^-> ssh-ed25519" "$FILE")
        echo -e "${GREEN}✓ Contains $COUNT ssh-ed25519 recipient(s) ${BLUE}(CORRECT for agenix)${NC}"
        echo ""
        echo -e "${BLUE}Recipients:${NC}"
        grep "^-> ssh-ed25519" "$FILE" | while read line; do
            echo "  $line"
        done
        echo ""
        echo -e "${GREEN}✓ This file is correctly formatted for agenix${NC}"
        return 0
    elif grep -q "^-> X25519" "$FILE"; then
        local COUNT=$(grep -c "^-> X25519" "$FILE")
        echo -e "${RED}✗ Contains $COUNT X25519 recipient(s) ${RED}(WRONG for agenix)${NC}"
        echo ""
        echo -e "${YELLOW}This file was encrypted with age keys instead of SSH keys.${NC}"
        echo -e "${YELLOW}Agenix requires SSH public key encryption!${NC}"
        echo ""
        echo -e "${BLUE}To fix:${NC}"
        echo "  1. Decrypt with your admin key:"
        echo "     nix-shell -p age --run \"age --decrypt -i ~/.ssh/agenix $FILE\" > /tmp/plain.txt"
        echo ""
        echo "  2. Re-encrypt with this script:"
        echo "     $0 -n $FILE -f /tmp/plain.txt"
        echo ""
        echo "  3. Clean up:"
        echo "     rm /tmp/plain.txt"
        return 1
    else
        echo -e "${RED}✗ No recognizable recipients found${NC}"
        return 1
    fi
}

# Parse command line arguments
OUTPUT_FILE=""
HOSTS="all"
ENV_FORMAT=false
INPUT_FILE=""
SECRET=""
VERIFY_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--hosts)
            HOSTS="$2"
            shift 2
            ;;
        -e|--env-format)
            ENV_FORMAT=true
            shift
            ;;
        -f|--file)
            INPUT_FILE="$2"
            shift 2
            ;;
        -s|--secret)
            SECRET="$2"
            shift 2
            ;;
        -v|--verify)
            VERIFY_FILE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Handle verify mode
if [ -n "$VERIFY_FILE" ]; then
    verify_secret "$VERIFY_FILE"
    exit $?
fi

# Validate output filename
if [ -z "$OUTPUT_FILE" ]; then
    echo -e "${RED}Error: Output filename is required (-n/--name)${NC}"
    usage
fi

# Check if we're in the secrets directory
if [ ! -f "secrets.nix" ]; then
    echo -e "${YELLOW}Warning: Not in the secrets directory. Current directory: $(pwd)${NC}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build SSH public key recipients file
RECIPIENTS_FILE=$(mktemp)
trap "rm -f $RECIPIENTS_FILE" EXIT

echo -e "${BLUE}Fetching SSH public keys...${NC}"

if [[ "$HOSTS" == "all" ]]; then
    echo -e "${BLUE}Recipients:${NC} david, pits, admin"
    ssh tristonyoder@$DAVID_HOST "cat /etc/ssh/ssh_host_ed25519_key.pub" >> "$RECIPIENTS_FILE" 2>/dev/null || { echo -e "${RED}Error: Failed to fetch david SSH key${NC}"; exit 1; }
    ssh tristonyoder@$PITS_HOST "cat /etc/ssh/ssh_host_ed25519_key.pub" >> "$RECIPIENTS_FILE" 2>/dev/null || { echo -e "${RED}Error: Failed to fetch pits SSH key${NC}"; exit 1; }
    cat "$ADMIN_SSH_KEY" >> "$RECIPIENTS_FILE" 2>/dev/null || { echo -e "${RED}Error: Admin SSH key not found at $ADMIN_SSH_KEY${NC}"; exit 1; }
else
    echo -e "${BLUE}Recipients:${NC} $HOSTS"
    IFS=',' read -ra HOST_LIST <<< "$HOSTS"
    for host in "${HOST_LIST[@]}"; do
        case $host in
            david)
                ssh tristonyoder@$DAVID_HOST "cat /etc/ssh/ssh_host_ed25519_key.pub" >> "$RECIPIENTS_FILE" 2>/dev/null || { echo -e "${RED}Error: Failed to fetch david SSH key${NC}"; exit 1; }
                ;;
            pits)
                ssh tristonyoder@$PITS_HOST "cat /etc/ssh/ssh_host_ed25519_key.pub" >> "$RECIPIENTS_FILE" 2>/dev/null || { echo -e "${RED}Error: Failed to fetch pits SSH key${NC}"; exit 1; }
                ;;
            admin)
                cat "$ADMIN_SSH_KEY" >> "$RECIPIENTS_FILE" 2>/dev/null || { echo -e "${RED}Error: Admin SSH key not found at $ADMIN_SSH_KEY${NC}"; exit 1; }
                ;;
            *)
                echo -e "${RED}Error: Unknown host '$host'. Valid: david, pits, admin, all${NC}"
                exit 1
                ;;
        esac
    done
fi

echo -e "${GREEN}✓ Fetched SSH public keys${NC}"

# Get the secret content
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

if [ -n "$SECRET" ]; then
    # Secret provided as argument
    echo "$SECRET" > "$TEMP_FILE"
elif [ -n "$INPUT_FILE" ]; then
    # Read from file
    if [ ! -f "$INPUT_FILE" ]; then
        echo -e "${RED}Error: Input file not found: $INPUT_FILE${NC}"
        exit 1
    fi
    cat "$INPUT_FILE" > "$TEMP_FILE"
else
    # Interactive input
    echo -e "${BLUE}Enter secret content:${NC}"
    if [ "$ENV_FORMAT" = true ]; then
        echo -e "${YELLOW}Format: KEY=value (e.g., API_TOKEN=abc123)${NC}"
    fi
    echo -e "${YELLOW}Press Ctrl+D when done (or Ctrl+C to cancel)${NC}"
    cat > "$TEMP_FILE"
fi

# Validate content
if [ ! -s "$TEMP_FILE" ]; then
    echo -e "${RED}Error: No secret content provided${NC}"
    exit 1
fi

# Check for environment variable format if requested
if [ "$ENV_FORMAT" = true ]; then
    if ! grep -q "=" "$TEMP_FILE"; then
        echo -e "${YELLOW}Warning: ENV format requested but no '=' found in content${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Show preview (first 50 chars)
PREVIEW=$(head -c 50 "$TEMP_FILE")
if [ ${#PREVIEW} -ge 50 ]; then
    PREVIEW="${PREVIEW}..."
fi
echo -e "${BLUE}Content preview:${NC} $PREVIEW"
echo -e "${BLUE}Output file:${NC} $OUTPUT_FILE"

# Confirm
read -p "Encrypt this secret? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

# Encrypt the secret using SSH public keys (-R flag)
# CRITICAL: We suppress stderr to avoid nix-shell warnings contaminating the output
echo -e "${BLUE}Encrypting with SSH public keys (-R flag)...${NC}"
if nix-shell -p age --run "age --encrypt -R \"$RECIPIENTS_FILE\" -o \"$OUTPUT_FILE\" \"$TEMP_FILE\"" 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully encrypted to: $OUTPUT_FILE${NC}"
    
    # Show file info
    FILE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
    echo -e "${BLUE}File size:${NC} $FILE_SIZE"
    
    # VERIFY: Check that we have ssh-ed25519 recipients (not X25519)
    echo ""
    echo -e "${BLUE}Verifying encryption format...${NC}"
    if grep -q "^-> ssh-ed25519" "$OUTPUT_FILE"; then
        RECIPIENT_COUNT=$(grep -c "^-> ssh-ed25519" "$OUTPUT_FILE")
        echo -e "${GREEN}✓ Correctly encrypted with $RECIPIENT_COUNT ssh-ed25519 recipient(s)${NC}"
        echo -e "${GREEN}✓ This file will work with agenix${NC}"
    elif grep -q "^-> X25519" "$OUTPUT_FILE"; then
        echo -e "${RED}✗ WARNING: File has X25519 recipients instead of ssh-ed25519!${NC}"
        echo -e "${RED}✗ This will NOT work with agenix (will get 'no identity matched')${NC}"
        echo -e "${YELLOW}Something went wrong. Please report this issue.${NC}"
        exit 1
    else
        echo -e "${YELLOW}⚠ Could not verify recipient format${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}Next steps:${NC}"
    echo "1. Declare in modules/secrets.nix:"
    SECRET_NAME="${OUTPUT_FILE%.age}"
    cat << EOF
   age.secrets.$SECRET_NAME = {
     file = ../secrets/$OUTPUT_FILE;
     owner = "service-user";
     group = "service-group";
     mode = "0400";
   };
EOF
    echo ""
    echo "2. Reference in your service configuration:"
    echo "   config.age.secrets.$SECRET_NAME.path"
    echo ""
    echo "3. Commit the encrypted file:"
    echo "   git add secrets/$OUTPUT_FILE"
    echo "   git commit -m \"Add $SECRET_NAME secret\""
    echo ""
    echo "4. Verify it works (optional):"
    echo "   $0 -v $OUTPUT_FILE"
else
    echo -e "${RED}✗ Encryption failed${NC}"
    echo -e "${YELLOW}Check that age is available and the recipients file is valid${NC}"
    exit 1
fi

