#!/bin/bash
# filepath: ssh_setup.sh

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

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# SSH config file path
SSH_CONFIG="/etc/ssh/sshd_config"

# Backup original config
if [[ ! -f "${SSH_CONFIG}.backup" ]]; then
    log "Creating backup of SSH config at ${SSH_CONFIG}.backup"
    cp "$SSH_CONFIG" "${SSH_CONFIG}.backup"
fi

log "Configuring SSH with secure defaults..."

# Function to update SSH configuration
update_ssh_config() {
    local setting="$1"
    local value="$2"

    if grep -q "^#\?${setting}" "$SSH_CONFIG"; then
        # Setting exists (commented or uncommented), replace it
        sed -i "s/^#\?${setting}.*/${setting} ${value}/" "$SSH_CONFIG"
        log "Updated: ${setting} ${value}"
    else
        # Setting doesn't exist, add it
        echo "${setting} ${value}" >> "$SSH_CONFIG"
        log "Added: ${setting} ${value}"
    fi
}

# Apply SSH configuration changes
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "UseDNS" "no"

# Validate SSH config before restarting
log "Validating SSH configuration..."
if sshd -t; then
    log "SSH configuration is valid"
else
    error "SSH configuration is invalid! Restoring backup..."
    cp "${SSH_CONFIG}.backup" "$SSH_CONFIG"
    exit 1
fi

# Restart SSH service
log "Restarting SSH service..."
if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
    log "SSH service restarted successfully"
else
    error "Failed to restart SSH service"
    exit 1
fi

# Verify service is running
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    log "SSH service is running"
else
    warning "SSH service may not be running properly"
fi

log "SSH configuration completed successfully!"
log "Remember to test SSH access before closing this session!"

