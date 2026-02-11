#!/usr/bin/env bash

# Run with sudo
# curl -fsSL https://sh.ameistad.com/debian_trixie/golang_latest.sh | sudo bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

GO_VERSION="1.25.3"

# Set variables
INSTALL_DIR="/usr/local"
TEMP_DIR=$(mktemp -d)
ARCH=$(detect_arch)
OS="linux"
FILENAME="go${GO_VERSION}.${OS}-${ARCH}.tar.gz"
DOWNLOAD_URL="https://go.dev/dl/${FILENAME}"

cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

print_status "Starting Go installation..."
print_status "Target version: $GO_VERSION"
print_status "Architecture: $ARCH"
print_status "Download URL: $DOWNLOAD_URL"

if ! command -v curl &> /dev/null; then
    print_status "Installing curl..."
    apt update && apt install -y curl
fi

cd "$TEMP_DIR"

if command -v go &> /dev/null; then
    CURRENT_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    print_info "Currently installed Go version: go$CURRENT_VERSION"

    if [[ "$CURRENT_VERSION" == "$GO_VERSION" ]]; then
        print_info "Target version is already installed!"
        read -p "Do you want to reinstall? (y/N): " -r </dev/tty
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled."
            exit 0
        fi
    fi
fi

print_status "Downloading Go $GO_VERSION..."
if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
    print_error "Failed to download Go from $DOWNLOAD_URL"
    print_status "Trying golang.org mirror..."
    DOWNLOAD_URL="https://golang.org/dl/${FILENAME}"
    if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
        print_error "Failed to download Go from both sources"
        print_error "Please check if version $GO_VERSION exists"
        exit 1
    fi
fi

if [[ ! -f "$FILENAME" ]]; then
    print_error "Downloaded file not found"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$FILENAME")
if [[ $FILE_SIZE -lt 50000000 ]]; then
    print_error "Downloaded file seems too small ($FILE_SIZE bytes)"
    print_error "This might indicate the version doesn't exist or download failed"
    exit 1
fi

print_status "Downloaded file size: $(( FILE_SIZE / 1024 / 1024 ))MB"

if ! file "$FILENAME" | grep -q "gzip compressed"; then
    print_error "Downloaded file is not a valid gzip archive"
    print_error "File type: $(file "$FILENAME")"
    exit 1
fi

if [[ -d "$INSTALL_DIR/go" ]]; then
    print_warning "Removing existing Go installation..."
    rm -rf "$INSTALL_DIR/go"
fi

print_status "Extracting Go to $INSTALL_DIR..."
if ! tar -C "$INSTALL_DIR" -xzf "$FILENAME"; then
    print_error "Failed to extract Go archive"
    exit 1
fi

chown -R root:root "$INSTALL_DIR/go"
chmod -R 755 "$INSTALL_DIR/go"

print_status "Setting up Go environment for all users..."
cat > /etc/profile.d/go.sh << 'EOF'
export GOROOT=/usr/local/go
export PATH=$PATH:$GOROOT/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

chmod 644 /etc/profile.d/go.sh

source /etc/profile.d/go.sh

print_status "Creating Go workspace template..."
mkdir -p /etc/skel/go/{bin,src,pkg}

cat > /usr/local/bin/setup-go-user << 'EOF'
#!/bin/bash

USER_GOPATH="$HOME/go"
if [[ ! -d "$USER_GOPATH" ]]; then
    echo "Creating Go workspace at $USER_GOPATH..."
    mkdir -p "$USER_GOPATH"/{bin,src,pkg}
    echo "Go workspace created successfully!"
    echo "GOPATH is set to: $USER_GOPATH"
else
    echo "Go workspace already exists at $USER_GOPATH"
fi

echo "Go environment:"
echo "GOROOT: ${GOROOT:-/usr/local/go}"
echo "GOPATH: ${GOPATH:-$HOME/go}"
if command -v go &> /dev/null; then
    echo "Go version: $(go version)"
else
    echo "Go binary not found in PATH"
fi
EOF

chmod +x /usr/local/bin/setup-go-user

print_status "Verifying Go installation..."
if "$INSTALL_DIR/go/bin/go" version &> /dev/null; then
    GO_VERSION_OUTPUT=$("$INSTALL_DIR/go/bin/go" version)
    print_status "Go installed successfully!"
    print_status "Version: $GO_VERSION_OUTPUT"
    print_status "Installation path: $INSTALL_DIR/go"
else
    print_error "Installation failed - Go binary not working"
    exit 1
fi

print_status "Installation complete!"
print_info "Go has been installed system-wide for all users."
print_info ""
print_info "Environment variables set in /etc/profile.d/go.sh:"
print_info "  GOROOT=/usr/local/go"
print_info "  GOPATH=\$HOME/go (per user)"
print_info "  PATH includes \$GOROOT/bin and \$GOPATH/bin"
print_info ""
print_info "For existing users to set up their Go workspace:"
print_info "  Run: setup-go-user"
print_info ""
print_info "To use Go immediately in current session:"
print_info "  Run: source /etc/profile.d/go.sh"
print_info "  Or restart your shell session"
print_info ""
print_info "To update to a newer version, edit the GO_VERSION variable at the top of this script."
