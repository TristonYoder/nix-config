#!/bin/bash

# NixOS Auto-Deployment Setup Script
# This script helps set up the initial configuration for auto-deployment

set -euo pipefail

echo "🚀 Setting up NixOS Auto-Deployment..."

# Check if we're on NixOS
if [ ! -f /etc/nixos/configuration.nix ]; then
    echo "❌ This script must be run on a NixOS system"
    exit 1
fi

# Check if Tailscale is installed
if ! command -v tailscale &> /dev/null; then
    echo "❌ Tailscale is not installed. Please install it first:"
    echo "   nix-env -iA nixpkgs.tailscale"
    exit 1
fi

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root (use sudo)"
    exit 1
fi

echo "✅ Prerequisites check passed"

# Create backup of current configuration
BACKUP_DIR="/var/lib/nixos-backups"
mkdir -p "$BACKUP_DIR"
BACKUP_NAME="nixos-backup-$(date +%Y%m%d-%H%M%S)"
cp -r /etc/nixos "$BACKUP_DIR/$BACKUP_NAME"
echo "📦 Configuration backed up to $BACKUP_DIR/$BACKUP_NAME"

# Generate SSH key for GitHub Actions
GITHUB_DEPLOY_HOME="/var/lib/github-deploy"
mkdir -p "$GITHUB_DEPLOY_HOME/.ssh"
chmod 700 "$GITHUB_DEPLOY_HOME/.ssh"

if [ ! -f "$GITHUB_DEPLOY_HOME/.ssh/id_ed25519" ]; then
    echo "🔑 Generating SSH key for GitHub Actions..."
    ssh-keygen -t ed25519 -C "github-actions@$(hostname)" -f "$GITHUB_DEPLOY_HOME/.ssh/id_ed25519" -N ""
    chown -R github-deploy:github-deploy "$GITHUB_DEPLOY_HOME"
    chmod 600 "$GITHUB_DEPLOY_HOME/.ssh/id_ed25519"
    chmod 644 "$GITHUB_DEPLOY_HOME/.ssh/id_ed25519.pub"
fi

echo "🔑 SSH key generated:"
echo "Public key (add this to GitHub secrets as SERVER_SSH_PUBLIC_KEY):"
cat "$GITHUB_DEPLOY_HOME/.ssh/id_ed25519.pub"
echo ""

# Get Tailscale IP
echo "🌐 Getting Tailscale information..."
if command -v tailscale &> /dev/null; then
    TAILSCALE_IP=$(tailscale status --json | jq -r '.Self.TailscaleIPs[0]' 2>/dev/null || echo "Not connected")
    TAILSCALE_HOSTNAME=$(tailscale status --json | jq -r '.Self.HostName' 2>/dev/null || echo "Not connected")
    
    echo "Tailscale IP: $TAILSCALE_IP"
    echo "Tailscale Hostname: $TAILSCALE_HOSTNAME"
    echo ""
    echo "📝 Add these to your GitHub secrets:"
    echo "   SERVER_HOSTNAME: $TAILSCALE_HOSTNAME"
    echo "   SERVER_USER: github-deploy"
    echo ""
else
    echo "⚠️  Tailscale not running. Please start it first:"
    echo "   sudo systemctl start tailscaled"
    echo "   sudo tailscale up"
fi

# Create GitHub Actions workflow directory
mkdir -p .github/workflows

echo "📁 GitHub Actions workflows created in .github/workflows/"
echo ""

# Display next steps
echo "🎯 Next Steps:"
echo "1. Add the following secrets to your GitHub repository:"
echo "   - TAILSCALE_OAUTH_CLIENT_ID"
echo "   - TAILSCALE_OAUTH_SECRET"
echo "   - SERVER_HOSTNAME: $TAILSCALE_HOSTNAME"
echo "   - SERVER_USER: github-deploy"
echo "   - GITHUB_REPO_OWNER: your-github-username"
echo "   - GITHUB_REPO_NAME: your-repo-name"
echo ""
echo "2. Set up Tailscale OAuth:"
echo "   - Go to https://login.tailscale.com/admin/settings/oauth"
echo "   - Create a new OAuth client"
echo "   - Set redirect URI to: https://github.com/settings/connections/applications/oauth"
echo ""
echo "3. Commit and push your changes:"
echo "   git add ."
echo "   git commit -m 'Add auto-deployment configuration'"
echo "   git push origin main"
echo ""
echo "4. Test the deployment by creating a pull request or pushing to main"
echo ""
echo "✅ Setup complete! Check the DEPLOYMENT_SETUP.md file for detailed instructions."
