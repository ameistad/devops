#!/usr/bin/env bash

# Run as root
# curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | bash
# curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | OPEN_TCP_PORTS="80,443" bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

OPEN_TCP_PORTS="${OPEN_TCP_PORTS:-}"
OPEN_UDP_PORTS="${OPEN_UDP_PORTS:-}"
SSH_PORTS="${SSH_PORTS:-}"
NFT_TABLE_NAME="server_hardening"

normalize_port_list() {
    local raw="${1:-}"
    local cleaned
    local port
    local result=""
    local seen=" "

    cleaned="${raw//,/ }"
    cleaned="${cleaned//;/ }"

    for port in $cleaned; do
        if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
            print_error "Invalid port: $port"
            exit 1
        fi

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
}

detect_ssh_ports() {
    local ports=""

    if [[ -n "$SSH_PORTS" ]]; then
        echo "$SSH_PORTS"
        return
    fi

    if command -v sshd &> /dev/null; then
        ports="$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | tr '\n' ' ')"
    fi

    if [[ -z "$ports" && -f /etc/ssh/sshd_config ]]; then
        ports="$(awk 'tolower($1) == "port" { print $2 }' /etc/ssh/sshd_config | tr '\n' ' ')"
    fi

    echo "${ports:-22}"
}

install_packages() {
    print_status "Installing hardening packages..."
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y \
        openssh-server \
        chrony \
        nftables \
        fail2ban \
        unattended-upgrades \
        apparmor \
        apparmor-utils \
        apparmor-profiles
}

write_nftables_config() {
    local tcp_ports="$1"
    local udp_ports="$2"

    if [[ -f /etc/nftables.conf && ! -f /etc/nftables.conf.pre-hardening ]]; then
        print_status "Backing up /etc/nftables.conf to /etc/nftables.conf.pre-hardening"
        cp /etc/nftables.conf /etc/nftables.conf.pre-hardening
    fi

    print_status "Writing nftables baseline firewall..."
    cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f

destroy table inet ${NFT_TABLE_NAME}

table inet ${NFT_TABLE_NAME} {
    chain input {
        type filter hook input priority filter; policy drop;

        iif "lo" accept
        ct state established,related accept
        ct state invalid drop

        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
EOF

    if [[ -n "$tcp_ports" ]]; then
        echo "        ct state new tcp dport { $tcp_ports } accept" >> /etc/nftables.conf
    fi

    if [[ -n "$udp_ports" ]]; then
        echo "        ct state new udp dport { $udp_ports } accept" >> /etc/nftables.conf
    fi

    cat >> /etc/nftables.conf << EOF

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

    ssh_ports="$(normalize_port_list "$(detect_ssh_ports)")"
    tcp_ports="$(normalize_port_list "$ssh_ports $OPEN_TCP_PORTS")"
    udp_ports="$(normalize_port_list "$OPEN_UDP_PORTS")"

    print_status "Configuring nftables firewall..."
    print_info "Allowed TCP ports: $tcp_ports"
    if [[ -n "$udp_ports" ]]; then
        print_info "Allowed UDP ports: $udp_ports"
    fi

    write_nftables_config "$tcp_ports" "$udp_ports"

    print_status "Validating nftables configuration..."
    nft -c -f /etc/nftables.conf

    systemctl enable nftables
    systemctl restart nftables

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

    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades

    print_status "Unattended upgrades are enabled with automatic reboot disabled."
}

configure_apparmor() {
    print_status "Enabling AppArmor service..."
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
    print_info "Firewall: nftables default-deny inbound, SSH preserved, optional ports from OPEN_TCP_PORTS/OPEN_UDP_PORTS."
    print_info "Time sync: chrony enabled with an immediate correction request."
    print_info "Fail2ban: sshd jail enabled with 5 retries in 10 minutes and 1 hour bans."
    print_info "Unattended upgrades: enabled with automatic reboot disabled."
    print_info "AppArmor: installed and enabled when supported by the kernel."

    if command -v ss &> /dev/null; then
        print_info "Listening sockets:"
        ss -tulpen || true
    fi
}

install_packages
ensure_root_authorized_keys
configure_ssh_root_key_only
configure_time_sync
configure_sysctl
configure_journald
configure_nftables
configure_fail2ban
configure_unattended_upgrades
configure_apparmor
print_summary
