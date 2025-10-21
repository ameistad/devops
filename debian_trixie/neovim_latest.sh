#!/usr/bin/env bash

set -euo pipefail

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

# Check if running as root (remove duplicate)
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

if ! API_RESPONSE=$(curl -s "https://api.github.com/repos/neovim/neovim/releases/latest"); then
    print_error "Failed to fetch release information from GitHub API"
    exit 1
fi

# Check if API response is valid JSON
if ! echo "$API_RESPONSE" | jq . >/dev/null 2>&1; then
    print_error "Invalid JSON response from GitHub API"
    print_error "Response: $API_RESPONSE"
    exit 1
fi

# Extract download URL for linux64 tarball (updated pattern)
DOWNLOAD_URL=$(echo "$API_RESPONSE" | jq -r '.assets[] | select(.name | test("nvim-linux64\\.tar\\.gz$")) | .browser_download_url')

if [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]]; then
    print_error "Could not find download URL for nvim-linux64.tar.gz"
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

# Check file size (should be > 1MB for a valid Neovim archive)
FILE_SIZE=$(stat -c%s "$FILENAME")
if [[ $FILE_SIZE -lt 1048576 ]]; then
    print_error "Downloaded file is too small ($FILE_SIZE bytes), likely corrupted"
    exit 1
fi

# Check if it's a valid gzip file
if ! file "$FILENAME" | grep -q "gzip compressed"; then
    print_error "Downloaded file is not a valid gzip archive"
    print_error "File type: $(file "$FILENAME")"
    exit 1
fi

# Extract the archive
print_status "Extracting Neovim..."
if ! tar xzf "$FILENAME"; then
    print_error "Failed to extract archive"
    exit 1
fi

# The extracted directory is nvim-linux64 (updated)
EXTRACTED_DIR="nvim-linux64"

# Verify extracted directory exists
if [[ ! -d "$EXTRACTED_DIR" ]]; then
    print_error "Expected directory '$EXTRACTED_DIR' not found after extraction"
    print_error "Available directories:"
    ls -la
    exit 1
fi

# Remove existing installations
for old_dir in "$INSTALL_DIR/nvim-linux64" "$INSTALL_DIR/nvim-linux-x86_64"; do
    if [[ -d "$old_dir" ]]; then
        print_warning "Removing existing Neovim installation: $(basename "$old_dir")"
        rm -rf "$old_dir"
    fi
done

# Move to installation directory
print_status "Installing Neovim to $INSTALL_DIR..."
mv "$EXTRACTED_DIR" "$INSTALL_DIR/"

# Create symlink for nvim binary
print_status "Creating symlink in /usr/local/bin..."
mkdir -p /usr/local/bin
ln -sf "$INSTALL_DIR/$EXTRACTED_DIR/bin/nvim" /usr/local/bin/nvim

# Create symlink for man pages
if [[ -d "$INSTALL_DIR/$EXTRACTED_DIR/share/man" ]]; then
    print_status "Setting up man pages..."
    mkdir -p /usr/local/share/man/man1
    ln -sf "$INSTALL_DIR/$EXTRACTED_DIR/share/man/man1/nvim.1" /usr/local/share/man/man1/nvim.1

    # Update man database
    if command -v mandb &> /dev/null; then
        print_status "Updating man database..."
        mandb -q 2>/dev/null || true
    fi
fi

# Verify installation
print_status "Verifying installation..."
if command -v nvim &> /dev/null; then
    NVIM_VERSION=$(nvim --version | head -n1)
    print_status "Neovim installed successfully!"
    print_status "Version: $NVIM_VERSION"
    print_status "Binary location: $(which nvim)"
else
    print_error "Installation failed - nvim command not found"
    print_error "PATH: $PATH"
    exit 1
fi

print_status "Installation complete! All users can now use 'nvim' command."
print_status "You may need to restart your shell or run 'hash -r' to refresh the command cache."

