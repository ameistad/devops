#!/usr/bin/env bash

# Run with sudo
# curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | sudo bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

# --- UFW Firewall ---

print_status "Installing and configuring UFW firewall..."
apt update && apt install -y ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp

print_status "Enabling UFW..."
ufw --force enable

print_status "UFW firewall configured and enabled."

# --- Fail2ban ---

print_status "Installing and configuring Fail2ban..."
apt install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = ssh
maxretry = 5
findtime = 600
bantime = 3600
backend = systemd
EOF

systemctl enable fail2ban
systemctl start fail2ban

print_status "Fail2ban configured and started."

# --- Unattended Upgrades ---

print_status "Installing and configuring unattended-upgrades..."
apt install -y unattended-upgrades

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

print_status "Unattended upgrades configured and started."

print_status "Server hardening complete!"
print_info "UFW: Denying all incoming traffic except SSH (port 22)."
print_info "Fail2ban: Banning IPs after 5 failed SSH attempts within 10 minutes for 1 hour."
print_info "Unattended upgrades: Daily security updates with weekly cache cleanup."
