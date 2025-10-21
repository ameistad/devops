#!/bin/bash

# Script to download and install latest Go for all users on Debian 13
# Requires root privileges

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
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}[NOTE]${NC} $1"
}

# Check if running as root - handle EUID safely
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Set variables
INSTALL_DIR="/usr/local"
TEMP_DIR=$(mktemp -d)
GO_API_URL="https://go.dev/dl/?mode=json"
ARCH="amd64"
OS="linux"

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Set trap to cleanup on exit
trap cleanup EXIT

print_status "Starting Go installation..."

# Check if curl and jq are installed
if ! command -v curl &> /dev/null; then
    print_status "Installing curl..."
    apt update && apt install -y curl
fi

if ! command -v jq &> /dev/null; then
    print_status "Installing jq..."
    apt update && apt install -y jq
fi

# Function to get Go version via web scraping
get_go_version_fallback() {
    print_status "Using fallback method to get Go version..."
    # Try multiple patterns to find the version
    local version
    version=$(curl -s https://go.dev/dl/ | grep -oP 'go1\.\d+\.\d+' | head -1)
    if [[ -z "$version" ]]; then
        version=$(curl -s https://golang.org/dl/ | grep -oP 'go1\.\d+\.\d+' | head -1)
    fi
    if [[ -z "$version" ]]; then
        # Try GitHub releases as last resort
        version=$(curl -s https://api.github.com/repos/golang/go/releases/latest | jq -r '.tag_name')
    fi
    echo "$version"
}

# Get the latest Go version info
print_status "Fetching latest Go version information..."
cd "$TEMP_DIR"

LATEST_VERSION=""

# Try the official API first
if curl -s -f -L "$GO_API_URL" -o go_releases.json; then
    if jq empty go_releases.json 2>/dev/null; then
        LATEST_VERSION=$(jq -r '.[0].version' go_releases.json)
        print_status "Got version from API: $LATEST_VERSION"
    else
        print_warning "API response is not valid JSON, trying fallback..."
        LATEST_VERSION=$(get_go_version_fallback)
    fi
else
    print_warning "API request failed, trying fallback..."
    LATEST_VERSION=$(get_go_version_fallback)
fi

# Final validation
if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
    print_error "Could not determine latest Go version"
    exit 1
fi

# Ensure version starts with 'go'
if [[ ! "$LATEST_VERSION" =~ ^go ]]; then
    LATEST_VERSION="go${LATEST_VERSION}"
fi

# Construct download filename and URL
FILENAME="${LATEST_VERSION}.${OS}-${ARCH}.tar.gz"
DOWNLOAD_URL="https://go.dev/dl/${FILENAME}"

print_status "Latest Go version: $LATEST_VERSION"
print_status "Download URL: $DOWNLOAD_URL"

# Check if Go is already installed and get current version
if command -v go &> /dev/null; then
    CURRENT_VERSION=$(go version | awk '{print $3}')
    print_info "Currently installed Go version: $CURRENT_VERSION"

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        print_info "Latest version is already installed!"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled."
            exit 0
        fi
    fi
fi

# Download latest Go
print_status "Downloading Go $LATEST_VERSION..."
if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
    print_error "Failed to download Go from $DOWNLOAD_URL"
    # Try golang.org mirror
    print_status "Trying golang.org mirror..."
    DOWNLOAD_URL="https://golang.org/dl/${FILENAME}"
    if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
        print_error "Failed to download Go from both sources"
        exit 1
    fi
fi

# Verify the download
if [[ ! -f "$FILENAME" ]]; then
    print_error "Downloaded file not found"
    exit 1
fi

# Check file size (Go releases are typically > 100MB)
FILE_SIZE=$(stat -c%s "$FILENAME")
if [[ $FILE_SIZE -lt 50000000 ]]; then  # Less than ~50MB suggests an error page
    print_error "Downloaded file seems too small ($FILE_SIZE bytes)"
    print_error "First 200 characters of downloaded file:"
    head -c 200 "$FILENAME"
    exit 1
fi

# Check if it's a valid tar.gz file
if ! file "$FILENAME" | grep -q "gzip compressed"; then
    print_error "Downloaded file is not a valid gzip archive"
    print_error "File type: $(file "$FILENAME")"
    exit 1
fi

# Remove existing Go installation
if [[ -d "$INSTALL_DIR/go" ]]; then
    print_warning "Removing existing Go installation..."
    rm -rf "$INSTALL_DIR/go"
fi

# Extract Go to /usr/local
print_status "Extracting Go to $INSTALL_DIR..."
if ! tar -C "$INSTALL_DIR" -xzf "$FILENAME"; then
    print_error "Failed to extract Go archive"
    exit 1
fi

# Set proper permissions
chown -R root:root "$INSTALL_DIR/go"
chmod -R 755 "$INSTALL_DIR/go"

# Create profile script for all users
print_status "Setting up Go environment for all users..."
cat > /etc/profile.d/go.sh << 'EOF'
# Go environment variables
export GOROOT=/usr/local/go
export PATH=$PATH:$GOROOT/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOF

chmod 644 /etc/profile.d/go.sh

# Source the profile for current session
source /etc/profile.d/go.sh

# Create GOPATH directory structure template
print_status "Creating Go workspace template..."
mkdir -p /etc/skel/go/{bin,src,pkg}

# For existing users, we'll create a helper script
cat > /usr/local/bin/setup-go-user << 'EOF'
#!/bin/bash
# Script to set up Go workspace for current user

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

# Verify installation
print_status "Verifying Go installation..."
if "$INSTALL_DIR/go/bin/go" version &> /dev/null; then
    GO_VERSION=$("$INSTALL_DIR/go/bin/go" version)
    print_status "Go installed successfully!"
    print_status "Version: $GO_VERSION"
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
