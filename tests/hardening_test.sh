#!/usr/bin/env bash
# Safe on a development machine: all host-facing commands below are mocked.
set -euo pipefail
cd "$(dirname "$0")/.."
source debian_trixie/hardening.sh

assert_equal() {
    if [[ "$1" != "$2" ]]; then
        printf 'Expected <%s>, got <%s>\n' "$2" "$1" >&2
        exit 1
    fi
}

assert_equal "$(normalize_port_list '22,080;443 80 00022 65535')" '22, 80, 443, 65535'
assert_equal "$(normalize_port_list '')" ''
for invalid in 0 65536 -1 '80-90' 'abc' '12345678901234567890' '*'; do
    if (normalize_port_list "$invalid") >/dev/null 2>&1; then
        printf 'Accepted invalid port: %s\n' "$invalid" >&2
        exit 1
    fi
done

ss() {
    if [[ "$*" == '-H -l -n -t' ]]; then
        cat <<'SOCKETS'
LISTEN 0 128 0.0.0.0:22 0.0.0.0:*
LISTEN 0 128 [::]:443 [::]:*
LISTEN 0 128 *:8080 *:*
LISTEN 0 128 10.0.0.2:9000 0.0.0.0:*
LISTEN 0 128 127.0.0.53:53 0.0.0.0:*
LISTEN 0 128 [::1]:5432 [::]:*
LISTEN 0 128 [::ffff:127.0.0.1]:6379 *:*
LISTEN 0 128 [fe80::123%eth0]:8081 [::]:*
LISTEN 0 128 [::]:22 [::]:*
SOCKETS
    else
        cat <<'SOCKETS'
UNCONN 0 0 0.0.0.0:51820 0.0.0.0:*
UNCONN 0 0 127.0.0.1:323 0.0.0.0:*
UNCONN 0 0 [::1]:323 [::]:*
UNCONN 0 0 [::]:51820 [::]:*
SOCKETS
    fi
}
assert_equal "$(normalize_port_list "$(detect_listening_ports t)")" '22, 443, 8080, 9000, 8081'
assert_equal "$(normalize_port_list "$(detect_listening_ports u)")" '51820'
snapshot_listening_ports >/dev/null
assert_equal "$(normalize_port_list "$DETECTED_TCP_PORTS 8443")" '22, 443, 8080, 9000, 8081, 8443'

ss() { return 1; }
if detect_listening_ports t >/dev/null 2>&1; then
    echo 'Failed socket inspection was accepted' >&2
    exit 1
fi
AUTO_DETECT_PORTS=0
DETECTED_TCP_PORTS=''
DETECTED_UDP_PORTS=''
snapshot_listening_ports
assert_equal "$DETECTED_TCP_PORTS$DETECTED_UDP_PORTS" ''

sshd() { printf 'port 2222\nport 2200\n'; }
SSH_CONNECTION='192.0.2.1 53100 192.0.2.2 2022'
assert_equal "$(normalize_port_list "$(detect_ssh_ports)")" '2222, 2200, 2022'
SSH_PORTS=2223
assert_equal "$(normalize_port_list "$(detect_ssh_ports)")" '2223, 2022'
SSH_PORTS=''
SSH_CONNECTION=''
sshd() { return 1; }
# Ignore host fallback config to test failure handling, rather than assuming port 22.
[[ -n "$(detect_ssh_ports)" ]]
echo 'Port detection regression tests passed.'

# Package hooks must never restart nftables; our temporary mask must be removed
# on both success and failure. Existing runtime masks belong to the operator.
package_test_dir="$(mktemp -d)"
trap 'rm -rf "$package_test_dir"' EXIT
export PACKAGE_TEST_LOG="$package_test_dir/commands"
systemctl() { printf '%s\n' "$*" >> "$PACKAGE_TEST_LOG"; }
apt-get() { return "${PACKAGE_TEST_FAIL:-0}"; }
readlink() { [[ "${PACKAGE_TEST_MASKED:-0}" == 1 ]] && echo /dev/null; }
export -f systemctl apt-get readlink
bash -ec 'source debian_trixie/hardening.sh; install_packages' >/dev/null
assert_equal "$(cat "$PACKAGE_TEST_LOG")" $'mask --runtime nftables.service\nunmask --runtime nftables.service'
: > "$PACKAGE_TEST_LOG"
if PACKAGE_TEST_FAIL=1 bash -ec 'source debian_trixie/hardening.sh; install_packages' >/dev/null; then
    echo 'Package installation failure was swallowed' >&2
    exit 1
fi
assert_equal "$(cat "$PACKAGE_TEST_LOG")" $'mask --runtime nftables.service\nunmask --runtime nftables.service'
: > "$PACKAGE_TEST_LOG"
PACKAGE_TEST_MASKED=1 bash -ec 'source debian_trixie/hardening.sh; install_packages' >/dev/null
assert_equal "$(cat "$PACKAGE_TEST_LOG")" ''
echo 'Package firewall protection tests passed.'
