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

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Set trap to cleanup on exit
trap cleanup EXIT

print_status "Starting Neovim installation..."

# Check if curl and jq are installed
if ! command -v curl &> /dev/null; then
    print_error "curl is required but not installed. Installing curl..."
    apt update && apt install -y curl
fi

if ! command -v jq &> /dev/null; then
    print_status "jq is required but not installed. Installing jq..."
    apt update && apt install -y jq
fi

# Get the latest release info from GitHub API
print_status "Fetching latest release information..."
cd "$TEMP_DIR"

API_RESPONSE=$(curl -s "https://api.github.com/repos/neovim/neovim/releases/latest")
if [[ $? -ne 0 ]]; then
    print_error "Failed to fetch release information from GitHub API"
    exit 1
fi

# Extract download URL for linux x86_64 tarball
DOWNLOAD_URL=$(echo "$API_RESPONSE" | jq -r '.assets[] | select(.name | test("nvim-linux-x86_64\\.tar\\.gz$")) | .browser_download_url')

if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
    print_error "Could not find download URL for nvim-linux-x86_64.tar.gz"
    print_error "Available assets:"
    echo "$API_RESPONSE" | jq -r '.assets[].name'
    exit 1
fi

VERSION=$(echo "$API_RESPONSE" | jq -r '.tag_name')
print_status "Found Neovim version: $VERSION"
print_status "Download URL: $DOWNLOAD_URL"

# Download latest Neovim
print_status "Downloading Neovim $VERSION..."
FILENAME=$(basename "$DOWNLOAD_URL")

if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
    print_error "Failed to download Neovim"
    exit 1
fi

# Verify the download
if [[ ! -f "$FILENAME" ]]; then
    print_error "Downloaded file not found"
    exit 1
fi

# Check if it's a valid gzip file
if ! file "$FILENAME" | grep -q "gzip compressed"; then
    print_error "Downloaded file is not a valid gzip archive"
    print_error "File type: $(file "$FILENAME")"
    print_error "File contents (first 100 bytes):"
    head -c 100 "$FILENAME"
    exit 1
fi

# Extract the archive
print_status "Extracting Neovim..."
if ! tar xzf "$FILENAME"; then
    print_error "Failed to extract archive"
    exit 1
fi

# The extracted directory will be nvim-linux-x86_64, not nvim-linux64
EXTRACTED_DIR="nvim-linux-x86_64"

# Remove existing installation if it exists
if [[ -d "$INSTALL_DIR/$EXTRACTED_DIR" ]]; then
    print_warning "Removing existing Neovim installation..."
    rm -rf "$INSTALL_DIR/$EXTRACTED_DIR"
fi

# Also remove old nvim-linux64 directory if it exists
if [[ -d "$INSTALL_DIR/nvim-linux64" ]]; then
    print_warning "Removing old Neovim installation (nvim-linux64)..."
    rm -rf "$INSTALL_DIR/nvim-linux64"
fi

# Move to installation directory
print_status "Installing Neovim to $INSTALL_DIR..."
mv "$EXTRACTED_DIR" "$INSTALL_DIR/"

# Create symlink for nvim binary
print_status "Creating symlink in /usr/local/bin..."
ln -sf "$INSTALL_DIR/$EXTRACTED_DIR/bin/nvim" /usr/local/bin/nvim

# Create symlink for man pages
if [[ -d "$INSTALL_DIR/$EXTRACTED_DIR/share/man" ]]; then
    print_status "Setting up man pages..."
    mkdir -p /usr/local/share/man/man1
    ln -sf "$INSTALL_DIR/$EXTRACTED_DIR/share/man/man1/nvim.1" /usr/local/share/man/man1/nvim.1
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
