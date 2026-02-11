#!/usr/bin/env bash

# Run as root
# curl -fsSL https://sh.ameistad.com/debian_trixie/initial_setup.sh | bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

echo "This script will perform the following actions:"
echo "1. Update system packages"
echo "2. Install essential packages"
echo "3. Create or update a user with sudo privileges"
echo "4. Set up the user's SSH key"
echo "5. Install dotfiles and set up zsh"

read -p "Enter the username to create/update for first user: " USERNAME </dev/tty
if [ -z "$USERNAME" ]; then
  echo "Username cannot be empty."
  exit 1
fi

read -p "Enter hostname: " NEW_HOSTNAME </dev/tty
if [ -z "$NEW_HOSTNAME" ]; then
  echo "Hostname cannot be empty."
  exit 1
fi

CURRENT_HOSTNAME=$(hostname)

hostnamectl set-hostname "$NEW_HOSTNAME"

echo "$NEW_HOSTNAME" > /etc/hostname

if grep -q "$CURRENT_HOSTNAME" /etc/hosts; then
  sed -i "s/\b$CURRENT_HOSTNAME\b/$NEW_HOSTNAME/g" /etc/hosts
else
  print_warning "$CURRENT_HOSTNAME not found in /etc/hosts."
fi

print_status "Hostname changed from '$CURRENT_HOSTNAME' to '$NEW_HOSTNAME'."

print_status "Updating system packages..."
apt update && apt upgrade -y

print_status "Installing essential packages..."
apt install -y sudo neovim curl python3 python3-pip git zsh openssh-server

print_status "Setting up the user..."
if id "$USERNAME" &>/dev/null; then
  print_status "User $USERNAME exists, skipping creation."
else
  adduser "$USERNAME"
fi
usermod -aG sudo "$USERNAME"

usermod -s "$(which zsh)" "$USERNAME"

SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chown "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"

curl -fsSL https://ameistad.com/pub_key.txt -o "$SSH_DIR/authorized_keys"
chown "$USERNAME:$USERNAME" "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

DOTFILES_DIR="/home/$USERNAME/dotfiles"
if [ -d "$DOTFILES_DIR" ]; then
  print_status "Dotfiles directory exists; pulling latest changes..."
  sudo -u "$USERNAME" git -C "$DOTFILES_DIR" pull
else
  sudo -u "$USERNAME" git clone https://github.com/ameistad/dotfiles "$DOTFILES_DIR"
fi
chown -R "$USERNAME:$USERNAME" "$DOTFILES_DIR"

ZSHRC="/home/$USERNAME/.zshrc"
[ -e "$ZSHRC" ] && rm -f "$ZSHRC"
ln -s "$DOTFILES_DIR/.zshrc" "$ZSHRC"
chown -h "$USERNAME:$USERNAME" "$ZSHRC"

LOCALRC="/home/$USERNAME/.localrc"
cat > "$LOCALRC" << 'EOF'
export PROJECTS_DIRECTORY=$HOME
EOF
chown "$USERNAME:$USERNAME" "$LOCALRC"
chmod 644 "$LOCALRC"

print_status "Setup complete. Please reboot."
