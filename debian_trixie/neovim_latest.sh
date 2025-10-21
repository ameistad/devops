#!/usr/bin/env bash

# Run with sudo
# curl -fsSL https://sh.ameistad.com/debian_trixie/neovim_latest.sh | sudo bash

set -euo pipefail

NEOVIM_VERSION="v0.11.4"

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
DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz"

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Set trap to cleanup on exit
trap cleanup EXIT

print_status "Starting Neovim installation..."
print_status "Target version: $NEOVIM_VERSION"
print_status "Download URL: $DOWNLOAD_URL"

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    print_error "curl is required but not installed. Installing curl..."
    apt update && apt install -y curl
fi

cd "$TEMP_DIR"

# Download Neovim
print_status "Downloading Neovim $NEOVIM_VERSION..."
FILENAME="nvim-linux-x86_64.tar.gz"

if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
    print_error "Failed to download Neovim from $DOWNLOAD_URL"
    print_error "Please check if version $NEOVIM_VERSION exists"
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
    print_error "Downloaded file is too small ($FILE_SIZE bytes), likely corrupted or version doesn't exist"
    exit 1
fi

print_status "Downloaded file size: $(( FILE_SIZE / 1024 / 1024 ))MB"

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

# The extracted directory could be either nvim-linux-x86_64 or nvim-linux64
# Let's detect which one exists
EXTRACTED_DIR=""
for dir in "nvim-linux-x86_64" "nvim-linux64"; do
    if [[ -d "$dir" ]]; then
        EXTRACTED_DIR="$dir"
        break
    fi
done

if [[ -z "$EXTRACTED_DIR" ]]; then
    print_error "Could not find extracted Neovim directory"
    print_error "Available directories:"
    ls -la
    exit 1
fi

print_status "Found extracted directory: $EXTRACTED_DIR"

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
    NVIM_VERSION_OUTPUT=$(nvim --version | head -n1)
    print_status "Neovim installed successfully!"
    print_status "Installed version: $NVIM_VERSION_OUTPUT"
    print_status "Binary location: $(which nvim)"
else
    print_error "Installation failed - nvim command not found"
    print_error "PATH: $PATH"
    exit 1
fi

print_status "Installation complete! All users can now use 'nvim' command."
print_status "You may need to restart your shell or run 'hash -r' to refresh the command cache."
print_status ""
print_status "To update to a newer version, simply edit the NEOVIM_VERSION variable at the top of this script."
