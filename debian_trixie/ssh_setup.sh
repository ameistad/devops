#!/usr/bin/env bash

# Run with sudo
# curl -fsSL https://sh.ameistad.com/debian_trixie/ssh_setup.sh | sudo bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

# SSH config file path
SSH_CONFIG="/etc/ssh/sshd_config"

# Backup original config
if [[ ! -f "${SSH_CONFIG}.backup" ]]; then
    print_status "Creating backup of SSH config at ${SSH_CONFIG}.backup"
    cp "$SSH_CONFIG" "${SSH_CONFIG}.backup"
fi

print_status "Configuring SSH with secure defaults..."

# Function to update SSH configuration
update_ssh_config() {
    local setting="$1"
    local value="$2"

    if grep -q "^#\?${setting}" "$SSH_CONFIG"; then
        sed -i "s/^#\?${setting}.*/${setting} ${value}/" "$SSH_CONFIG"
        print_status "Updated: ${setting} ${value}"
    else
        echo "${setting} ${value}" >> "$SSH_CONFIG"
        print_status "Added: ${setting} ${value}"
    fi
}

# Apply SSH configuration changes
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "UseDNS" "no"

# Validate SSH config before restarting
print_status "Validating SSH configuration..."
if sshd -t; then
    print_status "SSH configuration is valid"
else
    print_error "SSH configuration is invalid! Restoring backup..."
    cp "${SSH_CONFIG}.backup" "$SSH_CONFIG"
    exit 1
fi

# Restart SSH service
print_status "Restarting SSH service..."
if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
    print_status "SSH service restarted successfully"
else
    print_error "Failed to restart SSH service"
    exit 1
fi

# Verify service is running
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    print_status "SSH service is running"
else
    print_warning "SSH service may not be running properly"
fi

print_status "SSH configuration completed successfully!"
print_status "Remember to test SSH access before closing this session!"
