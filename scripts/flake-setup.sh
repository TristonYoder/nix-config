#!/usr/bin/env bash

# David's NixOS Flake Setup Script
# This script helps set up the flake-based configuration

set -e

echo "🚀 Setting up David's NixOS Flake Configuration"
echo "================================================"

# Check if we're in the right directory
if [ ! -f "flake.nix" ]; then
    echo "❌ Error: flake.nix not found. Please run this script from the project root."
    exit 1
fi

echo "✅ Found flake.nix"

# Check if nix is available
if ! command -v nix &> /dev/null; then
    echo "❌ Error: nix command not found. Please install Nix first."
    echo "   Visit: https://nixos.org/download.html"
    exit 1
fi

echo "✅ Nix is available"

# Check flake syntax
echo "🔍 Checking flake syntax..."
if nix flake check; then
    echo "✅ Flake syntax is valid"
else
    echo "❌ Flake syntax errors found. Please fix them before proceeding."
    exit 1
fi

# Show available configurations
echo ""
echo "📋 Available configurations:"
nix flake show

echo ""
echo "🔧 Available commands:"
echo "  Build system:     nix build .#nixosConfigurations.david.config.system.build.toplevel"
echo "  Deploy system:    sudo nixos-rebuild switch --flake .#david"
echo "  Development:      nix develop"
echo "  Update inputs:    nix flake update"
echo "  Check syntax:     nix flake check"

echo ""
echo "🎉 Flake setup complete!"
echo ""
echo "Next steps:"
echo "1. Review the configuration in flake.nix"
echo "2. Enable optional services by uncommenting them"
echo "3. Deploy with: sudo nixos-rebuild switch --flake .#david"
echo ""
echo "For more information, see README-FLAKE.md"
