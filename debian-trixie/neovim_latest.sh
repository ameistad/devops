#!/bin/bash

set -euo pipefail

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Set variables
INSTALL_DIR="/usr/local"
TEMP_DIR=$(mktemp -d)
NVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz"

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Set trap to cleanup on exit
trap cleanup EXIT

print_status "Starting Neovim installation..."

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    print_error "curl is required but not installed. Installing curl..."
    apt update && apt install -y curl
fi

# Download latest Neovim
print_status "Downloading latest Neovim..."
cd "$TEMP_DIR"
if ! curl -LO "$NVIM_URL"; then
    print_error "Failed to download Neovim"
    exit 1
fi

# Extract the archive
print_status "Extracting Neovim..."
tar xzf nvim-linux64.tar.gz

# Remove existing installation if it exists
if [[ -d "$INSTALL_DIR/nvim-linux64" ]]; then
    print_warning "Removing existing Neovim installation..."
    rm -rf "$INSTALL_DIR/nvim-linux64"
fi

# Move to installation directory
print_status "Installing Neovim to $INSTALL_DIR..."
mv nvim-linux64 "$INSTALL_DIR/"

# Create symlink for nvim binary
print_status "Creating symlink in /usr/local/bin..."
ln -sf "$INSTALL_DIR/nvim-linux64/bin/nvim" /usr/local/bin/nvim

# Create symlink for man pages
if [[ -d "$INSTALL_DIR/nvim-linux64/share/man" ]]; then
    print_status "Setting up man pages..."
    mkdir -p /usr/local/share/man/man1
    ln -sf "$INSTALL_DIR/nvim-linux64/share/man/man1/nvim.1" /usr/local/share/man/man1/nvim.1
fi

# Update man database
if command -v mandb &> /dev/null; then
    print_status "Updating man database..."
    mandb -q
fi

# Verify installation
if command -v nvim &> /dev/null; then
    NVIM_VERSION=$(nvim --version | head -n1)
    print_status "Neovim installed successfully!"
    print_status "Version: $NVIM_VERSION"
    print_status "Binary location: $(which nvim)"
else
    print_error "Installation failed - nvim command not found"
    exit 1
fi

print_status "Installation complete! All users can now use 'nvim' command."
print_status "You may need to restart your shell or run 'hash -r' to refresh the command cache."
