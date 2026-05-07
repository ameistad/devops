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

configure_ssh_root_key_only

print_status "SSH configuration completed successfully!"
print_status "Remember to test SSH access before closing this session!"
