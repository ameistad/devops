# Debian 13 (Trixie) Server Setup Scripts

Shell scripts for setting up and configuring Debian 13 (Trixie) servers. Each script can be run independently via curl.

## Prerequisites

The scripts are fetched with `curl`, so install it first:
```sh
apt update && apt install -y curl
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

The hardening script requires `/root/.ssh/authorized_keys` to exist before it disables password authentication. By default, the firewall opens only the detected SSH port. Add service ports explicitly with `OPEN_TCP_PORTS` or `OPEN_UDP_PORTS`:
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | OPEN_TCP_PORTS="80,443" bash
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
