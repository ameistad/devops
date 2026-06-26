#!/usr/bin/env bash

# Run as root
# curl -fsSL https://sh.ameistad.com/debian_trixie/verify_hardening.sh | bash

set -uo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

NFT_TABLE_NAME="server_hardening"
FAILURES=0
WARNINGS=0

pass() {
    print_status "PASS: $1"
}

fail() {
    print_error "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

warn() {
    print_warning "WARN: $1"
    WARNINGS=$((WARNINGS + 1))
}

command_exists() {
    command -v "$1" &> /dev/null
}

check_command() {
    local command_name="$1"

    if command_exists "$command_name"; then
        pass "$command_name is installed"
    else
        fail "$command_name is missing"
    fi
}

check_service_enabled() {
    local service="$1"

    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        pass "$service is enabled"
    else
        fail "$service is not enabled"
    fi
}

check_service_active() {
    local service="$1"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        pass "$service is active"
    else
        fail "$service is not active"
    fi
}

check_file_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"

    if [[ -f "$file" ]] && grep -Eq "$pattern" "$file"; then
        pass "$description"
    else
        fail "$description"
    fi
}

check_sysctl() {
    local key="$1"
    local expected="$2"
    local actual

    if ! actual="$(sysctl -n "$key" 2>/dev/null)"; then
        warn "$key is not available on this kernel"
        return
    fi

    if [[ "$actual" == "$expected" ]]; then
        pass "$key = $expected"
    else
        fail "$key expected $expected, got $actual"
    fi
}

get_sshd_value() {
    local key="$1"
    awk -v wanted="$key" '$1 == wanted { print $2; exit }' <<< "$SSHD_EFFECTIVE_CONFIG"
}

check_ssh() {
    local permit_root_login
    local password_authentication
    local kbd_interactive_authentication
    local pubkey_authentication
    local authorized_keys_mode
    local authorized_keys_owner

    print_info "Checking SSH hardening..."

    if ! command_exists sshd; then
        fail "sshd is missing"
        return
    fi

    if sshd -t; then
        pass "sshd configuration syntax is valid"
    else
        fail "sshd configuration syntax is invalid"
        return
    fi

    SSHD_EFFECTIVE_CONFIG="$(sshd -T -C user=root,host=localhost,addr=127.0.0.1)"
    permit_root_login="$(get_sshd_value permitrootlogin)"
    password_authentication="$(get_sshd_value passwordauthentication)"
    kbd_interactive_authentication="$(get_sshd_value kbdinteractiveauthentication)"
    pubkey_authentication="$(get_sshd_value pubkeyauthentication)"

    if [[ "$permit_root_login" == "prohibit-password" || "$permit_root_login" == "without-password" ]]; then
        pass "root SSH login is key-only"
    else
        fail "permitrootlogin expected prohibit-password/without-password, got ${permit_root_login:-unset}"
    fi

    if [[ "$password_authentication" == "no" ]]; then
        pass "SSH password authentication is disabled"
    else
        fail "passwordauthentication expected no, got ${password_authentication:-unset}"
    fi

    if [[ "$kbd_interactive_authentication" == "no" ]]; then
        pass "SSH keyboard-interactive authentication is disabled"
    else
        fail "kbdinteractiveauthentication expected no, got ${kbd_interactive_authentication:-unset}"
    fi

    if [[ "$pubkey_authentication" == "yes" ]]; then
        pass "SSH public key authentication is enabled"
    else
        fail "pubkeyauthentication expected yes, got ${pubkey_authentication:-unset}"
    fi

    if [[ -s /root/.ssh/authorized_keys ]]; then
        pass "/root/.ssh/authorized_keys exists and is not empty"
    else
        fail "/root/.ssh/authorized_keys is missing or empty"
    fi

    if [[ -d /root/.ssh ]]; then
        authorized_keys_owner="$(stat -c '%U:%G' /root/.ssh 2>/dev/null || true)"
        if [[ "$authorized_keys_owner" == "root:root" ]]; then
            pass "/root/.ssh is owned by root"
        else
            fail "/root/.ssh owner expected root:root, got ${authorized_keys_owner:-unknown}"
        fi
    else
        fail "/root/.ssh directory is missing"
    fi

    if [[ -f /root/.ssh/authorized_keys ]]; then
        authorized_keys_mode="$(stat -c '%a' /root/.ssh/authorized_keys 2>/dev/null || true)"
        authorized_keys_owner="$(stat -c '%U:%G' /root/.ssh/authorized_keys 2>/dev/null || true)"

        if [[ "$authorized_keys_mode" == "600" ]]; then
            pass "/root/.ssh/authorized_keys mode is 600"
        else
            fail "/root/.ssh/authorized_keys mode expected 600, got ${authorized_keys_mode:-unknown}"
        fi

        if [[ "$authorized_keys_owner" == "root:root" ]]; then
            pass "/root/.ssh/authorized_keys is owned by root"
        else
            fail "/root/.ssh/authorized_keys owner expected root:root, got ${authorized_keys_owner:-unknown}"
        fi
    fi

    check_file_contains "/etc/ssh/sshd_config.d/00-server-hardening.conf" '^PasswordAuthentication no$' "SSH hardening drop-in disables password auth"
}

check_time_sync() {
    print_info "Checking time synchronization..."
    check_command chronyc
    check_service_enabled chrony
    check_service_active chrony

    if command_exists chronyc && chronyc tracking &>/dev/null; then
        pass "chrony reports tracking status"
    else
        warn "chrony tracking status could not be confirmed"
    fi
}

check_sysctls() {
    print_info "Checking sysctl hardening..."

    check_file_contains "/etc/sysctl.d/99-server-hardening.conf" '^kernel\.dmesg_restrict = 1$' "server hardening sysctl file is present"

    check_sysctl kernel.dmesg_restrict 1
    check_sysctl kernel.kptr_restrict 2
    check_sysctl kernel.yama.ptrace_scope 1
    check_sysctl kernel.unprivileged_bpf_disabled 1
    check_sysctl net.core.bpf_jit_harden 2
    check_sysctl net.ipv4.tcp_syncookies 1
    check_sysctl net.ipv4.conf.all.accept_redirects 0
    check_sysctl net.ipv4.conf.default.accept_redirects 0
    check_sysctl net.ipv4.conf.all.secure_redirects 0
    check_sysctl net.ipv4.conf.default.secure_redirects 0
    check_sysctl net.ipv4.conf.all.send_redirects 0
    check_sysctl net.ipv4.conf.default.send_redirects 0
    check_sysctl net.ipv4.conf.all.accept_source_route 0
    check_sysctl net.ipv4.conf.default.accept_source_route 0
    check_sysctl net.ipv6.conf.all.accept_redirects 0
    check_sysctl net.ipv6.conf.default.accept_redirects 0
    check_sysctl net.ipv6.conf.all.accept_source_route 0
    check_sysctl net.ipv6.conf.default.accept_source_route 0
}

check_journald() {
    print_info "Checking journald persistence..."

    if [[ -d /var/log/journal ]]; then
        pass "/var/log/journal exists"
    else
        fail "/var/log/journal is missing"
    fi

    check_file_contains "/etc/systemd/journald.conf.d/99-server-hardening.conf" '^Storage=persistent$' "journald persistent storage is configured"
    check_file_contains "/etc/systemd/journald.conf.d/99-server-hardening.conf" '^SystemMaxUse=500M$' "journald system log size limit is configured"
    check_service_active systemd-journald
}

check_nftables() {
    local ruleset
    local ssh_ports
    local port

    print_info "Checking nftables firewall..."
    check_command nft
    check_service_enabled nftables
    check_service_active nftables

    if [[ -f /etc/nftables.conf ]] && nft -c -f /etc/nftables.conf; then
        pass "/etc/nftables.conf syntax is valid"
    else
        fail "/etc/nftables.conf syntax is invalid or missing"
    fi

    if ! command_exists nft; then
        return
    fi

    if nft list table inet "$NFT_TABLE_NAME" &>/dev/null; then
        pass "nftables table inet $NFT_TABLE_NAME exists"
    else
        fail "nftables table inet $NFT_TABLE_NAME is missing"
        return
    fi

    ruleset="$(nft list table inet "$NFT_TABLE_NAME" 2>/dev/null || true)"

    if grep -Eq 'type filter hook input priority filter; policy drop;' <<< "$ruleset"; then
        pass "nftables input chain has default drop policy"
    else
        fail "nftables input chain does not have default drop policy"
    fi

    if grep -Eq 'iif "lo" accept' <<< "$ruleset"; then
        pass "nftables allows loopback traffic"
    else
        fail "nftables loopback accept rule is missing"
    fi

    if grep -Eq 'ct state established,related accept' <<< "$ruleset"; then
        pass "nftables allows established and related traffic"
    else
        fail "nftables established/related accept rule is missing"
    fi

    ssh_ports="$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | tr '\n' ' ')"
    for port in ${ssh_ports:-22}; do
        if grep -Eq "tcp dport.*[ {,]${port}([ },]|$).*accept" <<< "$ruleset"; then
            pass "nftables allows SSH TCP port $port"
        else
            fail "nftables does not allow SSH TCP port $port"
        fi
    done
}

check_fail2ban() {
    print_info "Checking Fail2ban..."
    check_command fail2ban-client
    check_service_enabled fail2ban
    check_service_active fail2ban

    if command_exists fail2ban-client && fail2ban-client -t &>/dev/null; then
        pass "Fail2ban configuration is valid"
    else
        fail "Fail2ban configuration is invalid"
    fi

    check_file_contains "/etc/fail2ban/jail.d/sshd.local" '^enabled = true$' "Fail2ban sshd jail is enabled in local config"
    check_file_contains "/etc/fail2ban/jail.d/sshd.local" '^backend = systemd$' "Fail2ban sshd jail uses systemd backend"

    if command_exists fail2ban-client && fail2ban-client status sshd &>/dev/null; then
        pass "Fail2ban sshd jail is running"
    else
        fail "Fail2ban sshd jail is not running"
    fi
}

check_unattended_upgrades() {
    print_info "Checking unattended upgrades..."
    check_service_enabled unattended-upgrades

    check_file_contains "/etc/apt/apt.conf.d/20auto-upgrades" '^APT::Periodic::Update-Package-Lists "1";$' "APT periodic package list updates are enabled"
    check_file_contains "/etc/apt/apt.conf.d/20auto-upgrades" '^APT::Periodic::Unattended-Upgrade "1";$' "APT unattended upgrades are enabled"
    check_file_contains "/etc/apt/apt.conf.d/52unattended-upgrades-local" '^Unattended-Upgrade::Automatic-Reboot "false";$' "unattended upgrades automatic reboot is disabled"
}

check_apparmor() {
    print_info "Checking AppArmor..."
    check_command aa-status
    check_service_enabled apparmor

    if systemctl is-active --quiet apparmor 2>/dev/null; then
        pass "apparmor service is active"
    else
        warn "apparmor service is not active"
    fi

    if command_exists aa-status && aa-status --enabled &>/dev/null; then
        pass "AppArmor is enabled by the kernel"
    else
        warn "AppArmor is not enabled by the kernel"
    fi
}

check_packages() {
    local package

    print_info "Checking required packages..."
    for package in openssh-server chrony nftables fail2ban unattended-upgrades apparmor apparmor-utils apparmor-profiles; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            pass "$package is installed"
        else
            fail "$package is not installed"
        fi
    done
}

print_summary() {
    echo
    if (( FAILURES == 0 )); then
        print_status "Hardening verification passed with $WARNINGS warning(s)."
    else
        print_error "Hardening verification failed with $FAILURES failure(s) and $WARNINGS warning(s)."
        exit 1
    fi
}

check_packages
check_ssh
check_time_sync
check_sysctls
check_journald
check_nftables
check_fail2ban
check_unattended_upgrades
check_apparmor
print_summary
