#!/usr/bin/env bash

# Run as root
# curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | bash
# curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | OPEN_TCP_PORTS="80,443" bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    # shellcheck source=debian_trixie/common.sh
    source "$SCRIPT_DIR/common.sh"
else
    COMMON_SCRIPT="$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
    eval "$COMMON_SCRIPT"
fi

OPEN_TCP_PORTS="${OPEN_TCP_PORTS:-}"
OPEN_UDP_PORTS="${OPEN_UDP_PORTS:-}"
SSH_PORTS="${SSH_PORTS:-}"
NFT_TABLE_NAME="server_hardening"
AUTO_DETECT_PORTS="${AUTO_DETECT_PORTS:-1}"
DETECTED_TCP_PORTS=""
DETECTED_UDP_PORTS=""

normalize_port_list() (
    # Split separators without interpreting user input as filename patterns.
    set -f
    local raw="${1:-}"
    local cleaned
    local port
    local result=""
    local seen=" "

    cleaned="${raw//,/ }"
    cleaned="${cleaned//;/ }"

    for port in $cleaned; do
        if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
            print_error "Invalid port: $port"
            exit 1
        fi

        port=$((10#$port))

        if [[ "$seen" == *" $port "* ]]; then
            continue
        fi

        seen+="$port "
        if [[ -n "$result" ]]; then
            result+=", "
        fi
        result+="$port"
    done

    echo "$result"
)

detect_ssh_ports() {
    local ports=""

    if command -v sshd &> /dev/null; then
        ports="$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | tr '\n' ' ' || true)"
    fi

    if [[ -z "$ports" && -f /etc/ssh/sshd_config ]]; then
        ports="$(awk 'tolower($1) == "port" { print $2 }' /etc/ssh/sshd_config | tr '\n' ' ')"
    fi

    # Keep the actual port of this SSH session, including socket activation.
    local session_port
    read -r _ _ _ session_port <<< "${SSH_CONNECTION:-}"
    echo "${SSH_PORTS:-${ports:-22}} ${session_port:-}"
}

preflight() {
    if [[ ! -r /etc/os-release ]]; then
        print_error "Cannot identify the operating system. Debian 13 is required."
        exit 1
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" != debian || "${VERSION_ID:-}" != 13 ]]; then
        print_error "This script supports Debian 13 (Trixie), not ${PRETTY_NAME:-this OS}."
        exit 1
    fi
    if [[ ! -d /run/systemd/system ]] || ! command -v apt-get &>/dev/null; then
        print_error "A running systemd Debian host with apt-get is required."
        exit 1
    fi
    if [[ "$AUTO_DETECT_PORTS" != 0 && "$AUTO_DETECT_PORTS" != 1 ]]; then
        print_error "AUTO_DETECT_PORTS must be 0 or 1."
        exit 1
    fi
    # Reject bad input before installing packages or changing authentication.
    normalize_port_list "$OPEN_TCP_PORTS $OPEN_UDP_PORTS $SSH_PORTS" >/dev/null
    ensure_root_authorized_keys
}

detect_listening_ports() {
    local protocol="$1"
    local sockets
    # One protocol at a time keeps the local address in column four.
    if ! sockets="$(ss -H -l -n "-$protocol")"; then
        print_error "Cannot inspect listening sockets; refusing to apply an incomplete firewall."
        return 1
    fi
    awk '
        {
            endpoint = $4
            port = endpoint
            sub(/^.*:/, "", port)
            address = endpoint
            sub(/:[^:]*$/, "", address)
            gsub(/\[|\]/, "", address)
            sub(/%.*/, "", address)
            if (address == "::1" || address ~ /^127\./ || address ~ /^::ffff:127\./)
                next
            if (port ~ /^[0-9]+$/) print port
        }
    ' <<< "$sockets"
}

snapshot_listening_ports() {
    if [[ "$AUTO_DETECT_PORTS" == 1 ]]; then
        DETECTED_TCP_PORTS="$(detect_listening_ports t)"
        DETECTED_UDP_PORTS="$(detect_listening_ports u)"
        print_info "Detected TCP listeners: $(normalize_port_list "$DETECTED_TCP_PORTS")"
        print_info "Detected UDP listeners: $(normalize_port_list "$DETECTED_UDP_PORTS")"
        print_warning "Detected ports are allowed on all interfaces. Review the list; listeners may previously have been firewalled."
    fi
}

install_packages() (
    # Debian package hooks can try-restart nftables even on a reinstall, which
    # runs ExecStop and flushes Docker/other live tables. A runtime mask blocks
    # those hooks without stopping an active firewall. Preserve an existing mask.
    if [[ "$(readlink /run/systemd/system/nftables.service 2>/dev/null || true)" != /dev/null ]]; then
        systemctl mask --runtime nftables.service
        trap 'systemctl unmask --runtime nftables.service' EXIT
    fi

    print_status "Installing hardening packages..."
    apt-get update
    # Restore deleted package conffiles as well as installing/updating dependencies.
    DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confmiss \
        -o Dpkg::Options::=--force-confold install --reinstall -y \
        ca-certificates \
        iproute2 \
        procps \
        python3-systemd \
        openssh-server \
        chrony \
        nftables \
        fail2ban \
        unattended-upgrades \
        apparmor \
        apparmor-utils \
        apparmor-profiles
)

write_nftables_config() {
    local tcp_ports="$1"
    local udp_ports="$2"
    local config="$3"

    if [[ -f /etc/nftables.conf && ! -f /etc/nftables.conf.pre-hardening ]]; then
        print_status "Backing up /etc/nftables.conf to /etc/nftables.conf.pre-hardening"
        cp /etc/nftables.conf /etc/nftables.conf.pre-hardening
    fi

    print_status "Writing nftables baseline firewall..."
    cat > "$config" << EOF
#!/usr/sbin/nft -f

destroy table inet ${NFT_TABLE_NAME}

table inet ${NFT_TABLE_NAME} {
    chain input {
        type filter hook input priority filter; policy drop;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop

        ip protocol icmp accept
        meta l4proto ipv6-icmp accept
EOF

    if [[ -n "$tcp_ports" ]]; then
        echo "        ct state new tcp dport { $tcp_ports } accept" >> "$config"
    fi

    if [[ -n "$udp_ports" ]]; then
        echo "        ct state new udp dport { $udp_ports } accept" >> "$config"
    fi

    cat >> "$config" << EOF

        counter drop
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF
}

configure_nftables() {
    local ssh_ports
    local tcp_ports
    local udp_ports
    local candidate

    ssh_ports="$(normalize_port_list "$(detect_ssh_ports)")"
    tcp_ports="$(normalize_port_list "$ssh_ports $DETECTED_TCP_PORTS $OPEN_TCP_PORTS")"
    udp_ports="$(normalize_port_list "$DETECTED_UDP_PORTS $OPEN_UDP_PORTS")"

    print_status "Configuring nftables firewall..."
    print_info "Allowed TCP ports: $tcp_ports"
    if [[ -n "$udp_ports" ]]; then
        print_info "Allowed UDP ports: $udp_ports"
    fi

    candidate="$(mktemp /etc/nftables.conf.XXXXXX)"
    write_nftables_config "$tcp_ports" "$udp_ports" "$candidate"

    print_status "Validating and applying nftables configuration..."
    if ! nft -c -f "$candidate" || ! nft -f "$candidate"; then
        rm -f "$candidate"
        print_error "Firewall update failed; the previous configuration file was retained."
        return 1
    fi
    chmod 644 "$candidate"
    mv "$candidate" /etc/nftables.conf

    systemctl unmask nftables
    systemctl enable nftables
    # Restart runs ExecStop, which flushes ALL tables (including Docker/Fail2ban).
    # Starting an already-active service is a no-op; an inactive service loads
    # the same idempotent, table-scoped configuration we just validated.
    systemctl start nftables

    print_status "nftables firewall is enabled."
}

configure_fail2ban() {
    local ssh_ports

    ssh_ports="$(normalize_port_list "$(detect_ssh_ports)")"

    print_status "Configuring Fail2ban for sshd..."
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.local << EOF
[sshd]
enabled = true
port = $ssh_ports
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
ignoreip = 127.0.0.1/8 ::1
EOF

    fail2ban-client -t
    systemctl unmask fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban

    print_status "Fail2ban is enabled for sshd."
}

configure_unattended_upgrades() {
    print_status "Configuring unattended upgrades..."
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    cat > /etc/apt/apt.conf.d/52unattended-upgrades-local << 'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::SyslogEnable "true";
EOF

    systemctl unmask unattended-upgrades apt-daily.timer apt-daily-upgrade.timer
    systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades

    print_status "Unattended upgrades are enabled with automatic reboot disabled."
}

configure_apparmor() {
    print_status "Enabling AppArmor service..."
    systemctl unmask apparmor
    systemctl enable apparmor

    if systemctl restart apparmor; then
        print_status "AppArmor service restarted."
    else
        print_warning "AppArmor service did not restart cleanly. A reboot may be required."
    fi

    if command -v aa-status &> /dev/null && aa-status --enabled; then
        print_status "AppArmor is enabled."
    else
        print_warning "AppArmor is installed but not currently enabled by the kernel."
    fi
}

configure_sysctl() {
    print_status "Writing low-risk sysctl hardening..."
    cat > /etc/sysctl.d/99-server-hardening.conf << 'EOF'
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

    if sysctl --system; then
        print_status "Sysctl hardening applied."
    else
        print_warning "Some sysctl settings could not be applied on this kernel."
    fi
}

configure_journald() {
    print_status "Configuring persistent journald logs..."
    mkdir -p /etc/systemd/journald.conf.d /var/log/journal
    cat > /etc/systemd/journald.conf.d/99-server-hardening.conf << 'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
RuntimeMaxUse=100M
MaxRetentionSec=1month
EOF

    systemctl restart systemd-journald
    print_status "journald persistence is enabled."
}

print_summary() {
    print_status "Server hardening complete."
    print_info "SSH: root key login allowed; password and keyboard-interactive authentication disabled."
    print_info "Firewall: default-deny inbound; SSH, detected listeners, and explicit OPEN_TCP_PORTS/OPEN_UDP_PORTS allowed."
    print_info "Time sync: chrony enabled with an immediate correction request."
    print_info "Fail2ban: sshd jail enabled with 5 retries in 10 minutes and 1 hour bans."
    print_info "Unattended upgrades: enabled with automatic reboot disabled."
    print_info "AppArmor: installed and enabled when supported by the kernel."

    if command -v ss &> /dev/null; then
        print_info "Listening sockets:"
        ss -tulpen || true
    fi
}

main() {
    require_root
    preflight
    install_packages
    snapshot_listening_ports
    configure_ssh_root_key_only /etc/ssh/sshd_config
    configure_time_sync
    configure_sysctl
    configure_journald
    configure_nftables
    configure_fail2ban
    configure_unattended_upgrades
    configure_apparmor
    print_summary
}

# Also supports curl | bash; sourcing exposes helpers for regression tests.
if [[ "${BASH_SOURCE[0]:-}" == "$0" || -z "${BASH_SOURCE[0]:-}" ]]; then
    main "$@"
fi
