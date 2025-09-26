#!/bin/bash
set -euo pipefail

# Custom CLI Installation Script
echo "🚀 Setting up Custom CLI..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG=""

# Load configuration to get CLI name
if [[ -f "$SCRIPT_DIR/lib/logging.sh" && -f "$SCRIPT_DIR/lib/config.sh" ]]; then
    source "$SCRIPT_DIR/lib/logging.sh"
    source "$SCRIPT_DIR/lib/config.sh"
    config_load_defaults >/dev/null 2>&1
fi

# Detect shell and config file
if [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_CONFIG="$HOME/.zshrc"
    echo "📝 Detected zsh shell"
elif [[ "$SHELL" == *"bash"* ]]; then
    if [[ -f "$HOME/.bashrc" ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    else
        SHELL_CONFIG="$HOME/.bash_profile"
    fi
    echo "📝 Detected bash shell"
else
    echo "⚠️  Unknown shell, defaulting to .bashrc"
    SHELL_CONFIG="$HOME/.bashrc"
fi

echo "📂 Config file: $SHELL_CONFIG"

# Make scripts executable
chmod +x "$SCRIPT_DIR/bin/custom-cli"
echo "✅ Scripts are now executable"

# Check if PATH export already exists
PATH_EXPORT="export PATH=\"\$HOME/Repos/custom-cli:\$PATH\""
if grep -q "custom-cli" "$SHELL_CONFIG" 2>/dev/null; then
    echo "⚠️  PATH entry already exists in $SHELL_CONFIG"
else
    echo "" >> "$SHELL_CONFIG"
    echo "# Custom CLI" >> "$SHELL_CONFIG"
    echo "$PATH_EXPORT" >> "$SHELL_CONFIG"
    echo "✅ Added custom-cli to PATH in $SHELL_CONFIG"
fi

echo ""
echo "🎉 Installation complete!"
echo ""
echo "📋 Next steps:"
echo "1. Reload your shell configuration:"
echo "   source $SHELL_CONFIG"
echo ""
echo "2. Test the installation:"
echo "   ${CLI_NAME:-custom-cli} help"
echo ""
echo "3. Start your development environment:"
echo "   ${CLI_NAME:-custom-cli} start dashboard"
echo ""
echo "📖 For more information, see: $SCRIPT_DIR/README.md"