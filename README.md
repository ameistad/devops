# Debian 13 (Trixie) Server Setup Scripts

Shell scripts for setting up and configuring Debian 13 (Trixie) servers. Each script can be run independently via curl.

## Scripts

### Initial setup
Creates a user with sudo privileges, installs essential packages, sets hostname, configures root and user SSH keys, applies key-only SSH login, and configures dotfiles.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/initial_setup.sh | bash
```

### SSH hardening
Allows root login with SSH keys only and disables password authentication.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/ssh_setup.sh | sudo bash
```

### Server hardening
Sets up UFW firewall, Fail2ban, and unattended security upgrades.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/hardening.sh | sudo bash
```

### Install Go (latest)
Installs Go system-wide with environment configuration. Supports amd64 and arm64.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/golang_latest.sh | sudo bash
```

### Install Neovim (latest)
Installs Neovim from GitHub releases. Supports amd64 and arm64.
```sh
curl -fsSL https://sh.ameistad.com/debian_trixie/neovim_latest.sh | sudo bash
```

## Ghostty support
```bash
infocmp -x | ssh YOUR-SERVER -- tic -x -
```
