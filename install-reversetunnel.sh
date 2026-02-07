#!/bin/bash

# ReverseTunnel Auto Installer & Runner
# Download, install and run in one command

clear
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ⚡ ReverseTunnel Manager - Auto Installer ⚡"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    echo "Please run: sudo bash install-reversetunnel.sh"
    exit 1
fi

echo "📥 Downloading ReverseTunnel..."

RAW_URL="https://raw.githubusercontent.com/skyboy610/polintunnel/main/reversetunnel.sh"
INSTALL_PATH="/usr/local/bin/reversetunnel"

# Try wget first, then curl
if command -v wget &> /dev/null; then
    if ! wget -q --show-progress "$RAW_URL" -O "$INSTALL_PATH"; then
        echo "⚠️  Download from GitHub failed, installing from local copy..."

        if [ ! -f "./reversetunnel.sh" ]; then
            echo "❌ Installation failed. reversetunnel.sh not found."
            exit 1
        fi

        cp ./reversetunnel.sh "$INSTALL_PATH"
    fi
elif command -v curl &> /dev/null; then
    if ! curl -# -L "$RAW_URL" -o "$INSTALL_PATH"; then
        echo "⚠️  Download from GitHub failed, installing from local copy..."

        if [ ! -f "./reversetunnel.sh" ]; then
            echo "❌ Installation failed. reversetunnel.sh not found."
            exit 1
        fi

        cp ./reversetunnel.sh "$INSTALL_PATH"
    fi
else
    echo "❌ Neither wget nor curl found. Please install one of them first."
    exit 1
fi

echo "⚙️  Setting up..."
chmod +x "$INSTALL_PATH"

echo "🔗 Creating command aliases..."

# Bash aliases
if [ -f ~/.bashrc ]; then
    grep -q "alias rtunnel=" ~/.bashrc || echo "alias rtunnel='reversetunnel'" >> ~/.bashrc
    grep -q "alias rt=" ~/.bashrc || echo "alias rt='reversetunnel'" >> ~/.bashrc
fi

# Zsh aliases
if [ -f ~/.zshrc ]; then
    grep -q "alias rtunnel=" ~/.zshrc || echo "alias rtunnel='reversetunnel'" >> ~/.zshrc
    grep -q "alias rt=" ~/.zshrc || echo "alias rt='reversetunnel'" >> ~/.zshrc
fi

# Symlinks
ln -sf "$INSTALL_PATH" /usr/local/bin/rtunnel
ln -sf "$INSTALL_PATH" /usr/local/bin/rt

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Available commands:"
echo "  • reversetunnel"
echo "  • rtunnel"
echo "  • rt"
echo ""
echo "🚀 Starting ReverseTunnel Manager..."
sleep 1

exec "$INSTALL_PATH"
