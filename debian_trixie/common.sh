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

    # Non-login root shells (for example, plain `su`) may inherit a user PATH.
    local admin_dir
    for admin_dir in /usr/local/sbin /usr/sbin /sbin; do
        case ":${PATH:-}:" in
            *":$admin_dir:"*) ;;
            *) PATH="${PATH:+$PATH:}$admin_dir" ;;
        esac
    done
    export PATH
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

configure_ssh_root_key_only() (
    local ssh_config="${1:-/etc/ssh/sshd_config}"
    local ssh_dropin="${2:-/etc/ssh/sshd_config.d/00-server-hardening.conf}"
    local rollback_dir
    local include_line="Include $ssh_dropin"
    local effective_config
    local permit_root_login
    local password_authentication
    local kbd_interactive_authentication
    local pubkey_authentication

    if ! command -v sshd &> /dev/null; then
        print_error "Cannot find sshd. Ensure openssh-server is installed and /usr/sbin is in PATH."
        exit 1
    fi

    if [[ ! -f "$ssh_config" ]]; then
        if [[ -f /usr/share/openssh/sshd_config ]]; then
            print_status "Restoring missing SSH configuration from the packaged default..."
            install -D -m 644 /usr/share/openssh/sshd_config "$ssh_config"
        else
            print_error "$ssh_config and the packaged OpenSSH default are missing."
            exit 1
        fi
    fi

    rollback_dir="$(mktemp -d)"
    cp -p "$ssh_config" "$rollback_dir/sshd_config"
    if [[ -e "$ssh_dropin" ]]; then
        cp -p "$ssh_dropin" "$rollback_dir/dropin"
    fi
    trap 'status=$?
        if (( status != 0 )); then
            cp -p "$rollback_dir/sshd_config" "$ssh_config"
            if [[ -f "$rollback_dir/dropin" ]]; then
                cp -p "$rollback_dir/dropin" "$ssh_dropin"
            else
                rm -f "$ssh_dropin"
            fi
            print_error "SSH hardening failed; previous configuration restored."
        fi
        rm -rf "$rollback_dir"
    ' EXIT

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

    # sshd uses the first global value. Older configs may omit Include or put
    # explicit values before it, so place our managed Include first, once.
    {
        printf '%s\n' "$include_line"
        awk -v managed="$include_line" '$0 != managed' "$rollback_dir/sshd_config"
    } > "$ssh_config"

    # Fresh/minimal installations may lack host keys and the runtime directory.
    ssh-keygen -A
    mkdir -p /run/sshd
    print_status "Validating SSH configuration..."
    if sshd -t -f "$ssh_config"; then
        print_status "SSH configuration is valid"
    else
        print_error "SSH configuration is invalid!"
        exit 1
    fi

    effective_config="$(sshd -T -f "$ssh_config" -C user=root,host=localhost,addr=127.0.0.1)"
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

    print_status "Enabling and reloading SSH service..."
    systemctl unmask ssh
    systemctl enable ssh
    if systemctl reload-or-restart ssh; then
        print_status "SSH service reloaded successfully"
    else
        print_error "Failed to restart SSH service"
        exit 1
    fi

    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
        print_status "SSH service is running"
    else
        print_warning "SSH service may not be running properly"
    fi
)

configure_time_sync() {
    print_status "Configuring chrony time synchronization..."

    if ! command -v chronyc &> /dev/null; then
        print_error "chrony is not installed. Install the chrony package before configuring time sync."
        exit 1
    fi

    systemctl unmask chrony
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
