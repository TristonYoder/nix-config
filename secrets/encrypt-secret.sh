#!/usr/bin/env bash

# Secrets Encryption Helper Script
# Encrypts secrets for agenix using the correct method (age --encrypt with file input)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Host and admin keys (from secrets.nix)
DAVID_KEY="age19my5vpmrvl5u9ug4frpdmuuemjhdgemgqjm6xunknmfjf6efvdxs232kym"
PITS_KEY="age1jja99mf5qfczutr574nve8vhpt7azm8aq4ukqqrstdn0agud23nscazh6r"
ADMIN_KEY="age1m32sa7vq84004w6spg5tp7vzmszecxpp0da6z6dj8fxs70y34flshd46jq"

# Usage information
usage() {
    cat << EOF
${BLUE}Usage:${NC} $0 [OPTIONS]

${BLUE}Description:${NC}
  Encrypts secrets for agenix with proper recipients.

${BLUE}Options:${NC}
  -n, --name NAME         Output filename (e.g., my-secret.age)
  -h, --hosts HOSTS       Comma-separated host list: david,pits,all (default: all)
  -e, --env-format        Use environment variable format (KEY=value)
  -f, --file FILE         Read secret from file instead of stdin
  -s, --secret SECRET     Provide secret directly as argument
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

${BLUE}Recipients:${NC}
  david: Host key for david server
  pits:  Host key for pits server
  admin: Admin key for local secret management
  all:   All of the above (default)

EOF
    exit 0
}

# Parse command line arguments
OUTPUT_FILE=""
HOSTS="all"
ENV_FORMAT=false
INPUT_FILE=""
SECRET=""

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
        --help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

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

# Build recipient list
RECIPIENTS=()
if [[ "$HOSTS" == "all" ]]; then
    RECIPIENTS+=("-r" "$DAVID_KEY" "-r" "$PITS_KEY" "-r" "$ADMIN_KEY")
    echo -e "${BLUE}Recipients:${NC} david, pits, admin"
else
    IFS=',' read -ra HOST_LIST <<< "$HOSTS"
    for host in "${HOST_LIST[@]}"; do
        case $host in
            david)
                RECIPIENTS+=("-r" "$DAVID_KEY")
                ;;
            pits)
                RECIPIENTS+=("-r" "$PITS_KEY")
                ;;
            admin)
                RECIPIENTS+=("-r" "$ADMIN_KEY")
                ;;
            *)
                echo -e "${RED}Error: Unknown host '$host'. Valid: david, pits, admin, all${NC}"
                exit 1
                ;;
        esac
    done
    echo -e "${BLUE}Recipients:${NC} $HOSTS"
fi

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

# Encrypt the secret
echo -e "${BLUE}Encrypting...${NC}"
if nix-shell -p age --run "age --encrypt ${RECIPIENTS[*]} -o \"$OUTPUT_FILE\" \"$TEMP_FILE\""; then
    echo -e "${GREEN}✓ Successfully encrypted to: $OUTPUT_FILE${NC}"
    
    # Show file info
    FILE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
    echo -e "${BLUE}File size:${NC} $FILE_SIZE"
    
    # Count recipients
    RECIPIENT_COUNT=$(grep -c "-> X25519" "$OUTPUT_FILE" || true)
    echo -e "${BLUE}Recipients:${NC} $RECIPIENT_COUNT"
    
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
else
    echo -e "${RED}✗ Encryption failed${NC}"
    exit 1
fi

