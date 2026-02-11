#!/usr/bin/env bash

# Run with sudo
# curl -fsSL https://sh.ameistad.com/debian_trixie/neovim_latest.sh | sudo bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

NEOVIM_VERSION="v0.11.4"

# Map architecture to Neovim's naming convention
ARCH=$(detect_arch)
case "$ARCH" in
    amd64) NVIM_ARCH="x86_64" ;;
    arm64) NVIM_ARCH="aarch64" ;;
esac

# Set variables
INSTALL_DIR="/usr/local"
TEMP_DIR=$(mktemp -d)
FILENAME="nvim-linux-${NVIM_ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/${FILENAME}"

cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

print_status "Starting Neovim installation..."
print_status "Target version: $NEOVIM_VERSION"
print_status "Architecture: $NVIM_ARCH"
print_status "Download URL: $DOWNLOAD_URL"

if ! command -v curl &> /dev/null; then
    print_error "curl is required but not installed. Installing curl..."
    apt update && apt install -y curl
fi

cd "$TEMP_DIR"

print_status "Downloading Neovim $NEOVIM_VERSION..."

if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
    print_error "Failed to download Neovim from $DOWNLOAD_URL"
    print_error "Please check if version $NEOVIM_VERSION exists"
    exit 1
fi

if [[ ! -f "$FILENAME" ]]; then
    print_error "Downloaded file not found"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$FILENAME")
if [[ $FILE_SIZE -lt 1048576 ]]; then
    print_error "Downloaded file is too small ($FILE_SIZE bytes), likely corrupted or version doesn't exist"
    exit 1
fi

print_status "Downloaded file size: $(( FILE_SIZE / 1024 / 1024 ))MB"

if ! file "$FILENAME" | grep -q "gzip compressed"; then
    print_error "Downloaded file is not a valid gzip archive"
    print_error "File type: $(file "$FILENAME")"
    exit 1
fi

print_status "Extracting Neovim..."
if ! tar xzf "$FILENAME"; then
    print_error "Failed to extract archive"
    exit 1
fi

EXTRACTED_DIR=""
for dir in "nvim-linux-x86_64" "nvim-linux-aarch64" "nvim-linux64"; do
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

for old_dir in "$INSTALL_DIR/nvim-linux64" "$INSTALL_DIR/nvim-linux-x86_64" "$INSTALL_DIR/nvim-linux-aarch64"; do
    if [[ -d "$old_dir" ]]; then
        print_warning "Removing existing Neovim installation: $(basename "$old_dir")"
        rm -rf "$old_dir"
    fi
done

print_status "Installing Neovim to $INSTALL_DIR..."
mv "$EXTRACTED_DIR" "$INSTALL_DIR/"

print_status "Creating symlink in /usr/local/bin..."
mkdir -p /usr/local/bin
ln -sf "$INSTALL_DIR/$EXTRACTED_DIR/bin/nvim" /usr/local/bin/nvim

if [[ -d "$INSTALL_DIR/$EXTRACTED_DIR/share/man" ]]; then
    print_status "Setting up man pages..."
    mkdir -p /usr/local/share/man/man1
    ln -sf "$INSTALL_DIR/$EXTRACTED_DIR/share/man/man1/nvim.1" /usr/local/share/man/man1/nvim.1

    if command -v mandb &> /dev/null; then
        print_status "Updating man database..."
        mandb -q 2>/dev/null || true
    fi
fi

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
