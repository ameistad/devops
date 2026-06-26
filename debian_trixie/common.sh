#!/usr/bin/env bash

# Shared library for debian_trixie scripts.
# Sourced by all other scripts in this directory.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[NOTE]${NC} $1"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

ensure_root_authorized_keys() {
    if [[ ! -s /root/.ssh/authorized_keys ]]; then
        print_error "/root/.ssh/authorized_keys is missing or empty."
        print_error "Add your SSH public key for root before disabling password authentication."
        exit 1
    fi

    chown root:root /root/.ssh /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys
}

configure_ssh_root_key_only() {
    local ssh_config="${1:-/etc/ssh/sshd_config}"
    local ssh_dropin="/etc/ssh/sshd_config.d/00-server-hardening.conf"
    local effective_config
    local permit_root_login
    local password_authentication
    local kbd_interactive_authentication
    local pubkey_authentication

    if [[ ! -f "${ssh_config}.backup" ]]; then
        print_status "Creating backup of SSH config at ${ssh_config}.backup"
        cp "$ssh_config" "${ssh_config}.backup"
    fi

    print_status "Configuring SSH to allow root key login and disable password authentication..."

    mkdir -p "$(dirname "$ssh_dropin")"
    cat > "$ssh_dropin" << 'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
UseDNS no
EOF
    print_status "Wrote SSH hardening drop-in: $ssh_dropin"

    print_status "Validating SSH configuration..."
    if sshd -t; then
        print_status "SSH configuration is valid"
    else
        print_error "SSH configuration is invalid!"
        exit 1
    fi

    effective_config="$(sshd -T -C user=root,host=localhost,addr=127.0.0.1)"
    permit_root_login="$(awk '$1 == "permitrootlogin" { print $2; exit }' <<< "$effective_config")"
    password_authentication="$(awk '$1 == "passwordauthentication" { print $2; exit }' <<< "$effective_config")"
    kbd_interactive_authentication="$(awk '$1 == "kbdinteractiveauthentication" { print $2; exit }' <<< "$effective_config")"
    pubkey_authentication="$(awk '$1 == "pubkeyauthentication" { print $2; exit }' <<< "$effective_config")"

    if [[ "$permit_root_login" != "prohibit-password" && "$permit_root_login" != "without-password" ]]; then
        print_error "Effective SSH setting is not hardened: permitrootlogin $permit_root_login"
        exit 1
    fi

    if [[ "$password_authentication" != "no" ]]; then
        print_error "Effective SSH setting is not hardened: passwordauthentication $password_authentication"
        exit 1
    fi

    if [[ "$kbd_interactive_authentication" != "no" ]]; then
        print_error "Effective SSH setting is not hardened: kbdinteractiveauthentication $kbd_interactive_authentication"
        exit 1
    fi

    if [[ "$pubkey_authentication" != "yes" ]]; then
        print_error "Effective SSH setting is not hardened: pubkeyauthentication $pubkey_authentication"
        exit 1
    fi

    print_status "Effective SSH configuration is hardened"

    print_status "Restarting SSH service..."
    if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
        print_status "SSH service restarted successfully"
    else
        print_error "Failed to restart SSH service"
        exit 1
    fi

    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        print_status "SSH service is running"
    else
        print_warning "SSH service may not be running properly"
    fi
}

configure_time_sync() {
    print_status "Configuring chrony time synchronization..."

    if ! command -v chronyc &> /dev/null; then
        print_error "chrony is not installed. Install the chrony package before configuring time sync."
        exit 1
    fi

    systemctl enable chrony
    systemctl restart chrony

    if chronyc -a makestep &> /dev/null; then
        print_status "chrony is enabled and an immediate time correction was requested."
    else
        print_warning "chrony is enabled, but immediate time correction could not be confirmed yet."
    fi
}

detect_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)
            print_error "Unsupported architecture: $machine"
            exit 1
            ;;
    esac
}
