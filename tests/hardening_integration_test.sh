#!/usr/bin/env bash
# Run ONLY in a disposable Debian 13 container with CAP_NET_ADMIN.
# This changes /etc/nftables.conf, SSH host keys, and the container firewall.
set -euo pipefail
cd "$(dirname "$0")/.."
source debian_trixie/hardening.sh
require_root
[[ -f /.dockerenv ]] || { echo 'Use a disposable Docker container.' >&2; exit 1; }
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Real sshd validation; service management is unavailable in this container.
systemctl() { printf '%s\n' "$*" >> "$work_dir/systemctl.log"; }
export -f systemctl
export work_dir
ssh_config="$work_dir/sshd_config"
ssh_dropin="$work_dir/00-server-hardening.conf"
cat > "$ssh_config" <<'CONFIG'
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PubkeyAuthentication no
CONFIG
configure_ssh_root_key_only "$ssh_config" "$ssh_dropin"
configure_ssh_root_key_only "$ssh_config" "$ssh_dropin"
[[ "$(grep -c "^Include $ssh_dropin$" "$ssh_config")" == 1 ]]
grep -qx 'passwordauthentication no' <<< "$(sshd -T -f "$ssh_config")"

# Invalid syntax must restore BOTH files without reloading the service.
printf '\nInvalidDirective yes\n' >> "$ssh_config"
cp "$ssh_config" "$work_dir/expected-config"
cp "$ssh_dropin" "$work_dir/expected-dropin"
cp "$work_dir/systemctl.log" "$work_dir/expected-services"
if bash -ec 'source debian_trixie/common.sh; configure_ssh_root_key_only "$1" "$2"' bash "$ssh_config" "$ssh_dropin"; then
    echo 'Invalid SSH configuration was accepted' >&2
    exit 1
fi
cmp "$ssh_config" "$work_dir/expected-config"
cmp "$ssh_dropin" "$work_dir/expected-dropin"
cmp "$work_dir/systemctl.log" "$work_dir/expected-services"

# Match blocks that defeat the requested policy also roll back.
cat > "$ssh_config" <<'CONFIG'
Match User root
    PasswordAuthentication yes
CONFIG
cp "$ssh_config" "$work_dir/expected-config"
if bash -ec 'source debian_trixie/common.sh; configure_ssh_root_key_only "$1" "$2"' bash "$ssh_config" "$ssh_dropin"; then
    echo 'Conflicting SSH Match block was accepted' >&2
    exit 1
fi
cmp "$ssh_config" "$work_dir/expected-config"
cmp "$ssh_dropin" "$work_dir/expected-dropin"

# Restore a missing sshd_config from the packaged template.
rm "$ssh_config"
configure_ssh_root_key_only "$ssh_config" "$ssh_dropin"

# Real ss output with non-loopback and loopback TCP/UDP sockets.
python3 -u - <<'PY' > "$work_dir/listeners" &
import socket, time
sockets = []
for family, kind, address in [
    (socket.AF_INET, socket.SOCK_STREAM, '0.0.0.0'),
    (socket.AF_INET6, socket.SOCK_STREAM, '::1'),
    (socket.AF_INET, socket.SOCK_DGRAM, '0.0.0.0'),
    (socket.AF_INET, socket.SOCK_DGRAM, '127.0.0.1'),
]:
    s = socket.socket(family, kind)
    s.bind((address, 0))
    if kind == socket.SOCK_STREAM:
        s.listen()
    sockets.append(s)
    print(s.getsockname()[1], flush=True)
time.sleep(120)
PY
listener_pid=$!
trap 'kill "$listener_pid" 2>/dev/null || true; rm -rf "$work_dir"' EXIT
for ((i=0; i<50; i++)); do
    [[ "$(wc -l < "$work_dir/listeners")" == 4 ]] && break
    sleep 0.1
done
mapfile -t ports < "$work_dir/listeners"
[[ "${#ports[@]}" == 4 ]]
snapshot_listening_ports
grep -qx "${ports[0]}" <<< "$DETECTED_TCP_PORTS"
if grep -qx "${ports[1]}" <<< "$DETECTED_TCP_PORTS"; then exit 1; fi
grep -qx "${ports[2]}" <<< "$DETECTED_UDP_PORTS"
if grep -qx "${ports[3]}" <<< "$DETECTED_UDP_PORTS"; then exit 1; fi

# Validate/apply twice, preserving an unrelated runtime table.
nft() {
    if [[ "${NFT_FORCE_FAILURE:-0}" == 1 ]]; then return 1; fi
    command nft "$@"
}
nft destroy table inet unrelated_test
nft add table inet unrelated_test
SSH_PORTS=2222
OPEN_TCP_PORTS=8443
OPEN_UDP_PORTS=51820
configure_nftables
configure_nftables
nft list table inet unrelated_test
nft list table inet server_hardening > "$work_dir/rules"
grep -q 'policy drop' "$work_dir/rules"
grep -q '8443' "$work_dir/rules"
grep -q '51820' "$work_dir/rules"
grep -q "${ports[0]}" "$work_dir/rules"
grep -q "${ports[2]}" "$work_dir/rules"
if grep -q 'restart nftables' "$work_dir/systemctl.log"; then exit 1; fi

# A failed validation must leave the persistent and live firewall unchanged.
cp /etc/nftables.conf "$work_dir/expected-nft"
NFT_FORCE_FAILURE=1
if configure_nftables; then
    echo 'Invalid nftables configuration was accepted' >&2
    exit 1
fi
cmp /etc/nftables.conf "$work_dir/expected-nft"
NFT_FORCE_FAILURE=0
nft list table inet server_hardening > "$work_dir/rules-after"
cmp "$work_dir/rules" "$work_dir/rules-after"
echo 'Debian SSH, socket detection, and nftables integration tests passed.'
