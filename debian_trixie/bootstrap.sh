#!/usr/bin/env bash

# Run as root
# curl -fsSL https://sh.ameistad.com/debian_trixie/bootstrap.sh | bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

print_status "Installing shared setup prerequisites..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates \
    gzip \
    tar \
    git \
    zsh \
    openssh-server

print_status "Bootstrap complete."
