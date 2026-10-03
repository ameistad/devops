# Debian 13 (Trixie) Server Setup Scripts

Shell scripts for setting up and configuring Debian 13 (Trixie) servers. Each script can be run independently via curl.

## Prerequisites

The scripts are fetched with `curl`, so install it first:
```sh
apt update && apt install -y curl
```

The scripts add missing administrative directories to `PATH` for non-login root shells. If an older published script fails with `sshd: command not found` or `usermod: command not found`, run this as root, then rerun the setup command:
```sh
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"
```

## Scripts

### Bootstrap
Installs shared prerequisites used by the setup scripts: certificates, chrony time synchronization, gzip, tar, git, zsh, and OpenSSH server.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/bootstrap.sh | bash
```

### Server hardening
Applies a conservative root-only hardening baseline: root SSH key login is allowed, password SSH login is disabled, chrony time synchronization is enabled, nftables uses default-deny inbound firewalling, Fail2ban protects sshd, unattended upgrades run without automatic reboots, AppArmor tooling is enabled, journald logs are persistent, and low-risk sysctl settings are applied.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | bash
```

The script can run on Debian 13 servers that have not run bootstrap or earlier versions of these scripts. It checks the OS, systemd, port options, and a nonempty `/root/.ssh/authorized_keys` before installing packages or changing SSH. It installs/updates and reinstalls its required packages to restore missing package configuration, repairs missing SSH configuration and Include handling, enables the hardening services and APT timers, and reapplies the managed settings. It does not perform a distribution upgrade or upgrade unrelated packages. Conflicting SSH `Match` rules detected by the root-policy check cause validation to fail and the previous SSH configuration to be restored.

By default, it detects current TCP listeners and unconnected UDP sockets on non-loopback IPv4/IPv6 addresses using `ss`, and allows those ports along with SSH. No port environment variables are required for running services. Each run takes a fresh snapshot after dependency installation and prints the detected ports. This is local socket discovery, not an external reachability scan: it can allow a listener that was previously blocked, and the resulting port rules apply to all interfaces. Review the printed list.

Use `OPEN_TCP_PORTS` / `OPEN_UDP_PORTS` to add ports for services that are stopped or will be installed later:
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | OPEN_TCP_PORTS="80,443" bash
```

To disable discovery and allow only SSH plus your explicit ports:
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | AUTO_DETECT_PORTS=0 OPEN_TCP_PORTS="80,443" bash
```

`SSH_PORTS` can override the configured SSH port list; the current SSH session's server port is also retained when `SSH_CONNECTION` is available. Environment port lists accept commas, semicolons, or spaces. Loopback-only listeners, stopped services, container ports published solely through NAT, and upstream/cloud firewall rules cannot be inferred from this snapshot. Container forwarding is outside this input-chain baseline. Explicit extra ports must be supplied again on subsequent runs if they are not listening then.

The script owns `/etc/nftables.conf` and backs up its original content to `/etc/nftables.conf.pre-hardening`. It validates the candidate before applying it and replaces only its own live table, without restarting nftables and flushing other live tables. During package installation, a temporary runtime mask also prevents package hooks from restarting nftables; an existing runtime mask is preserved. Other firewall rules may still deny traffic; any custom persistent configuration in the original file must be merged manually before reboot. SSH configuration is backed up to `/etc/ssh/sshd_config.backup`. Test a new SSH connection before closing your existing session.

Verify the applied hardening state without changing server configuration:
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/verify_hardening.sh | bash
```

### Root dotfiles
Installs root shell/editor prerequisites including `fzf`, clones or updates dotfiles in `/root/dotfiles`, links `/root/.zshrc` and `/root/.config/nvim`, writes `/root/.localrc`, and sets root's shell to zsh.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/dotfiles_setup.sh | bash
```

### SSH policy only
Applies the same root key-only SSH policy without the rest of the hardening baseline.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/ssh_setup.sh | bash
```

### Install Go (latest)
Installs Go system-wide with environment configuration. Supports amd64 and arm64.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/golang_latest.sh | bash
```

### Install Neovim (latest)
Installs Neovim from GitHub releases. Supports amd64 and arm64.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/neovim_latest.sh | bash
```

## Ghostty support
```bash
infocmp -x | ssh YOUR-SERVER -- tic -x -
```

## Development checks

Run portable port parsing/detection regressions with `bash tests/hardening_test.sh`.
`tests/hardening_integration_test.sh` runs real OpenSSH validation, socket discovery, and nftables validation/application, including reruns and rollback paths. Run it only in a disposable Debian 13 Docker container with `--cap-add NET_ADMIN`, this repository mounted at `/work`, and `openssh-server`, `iproute2`, `nftables`, and `python3` installed. Service commands are mocked because the container does not run systemd.
