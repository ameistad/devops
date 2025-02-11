#!/bin/bash
set -e

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Prompt for username
read -p "Enter the username to create/update for first user: " USERNAME
if [ -z "$USERNAME" ]; then
  echo "Username cannot be empty."
  exit 1
fi

echo "Updating system packages..."
apt update && apt upgrade -y

echo "Installing essential packages..."
apt install -y sudo vim curl python3 python3-pip git software-properties-common zsh openssh-server ansible

echo "Setting up the user..."
if id "$USERNAME" &>/dev/null; then
  echo "User $USERNAME exists, skipping creation."
else
  adduser "$USERNAME"
fi
usermod -aG sudo "$USERNAME"

# Create .ssh directory with correct permissions
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chown "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Fetch the public key and store it as id_ed25519.pub
curl -fsSL https://ameistad.com/pub_key.txt -o "$SSH_DIR/id_ed25519.pub"
chown "$USERNAME:$USERNAME" "$SSH_DIR/id_ed25519.pub"
chmod 600 "$SSH_DIR/id_ed25519.pub"

# Clone the dotfiles repository and set ownership
DOTFILES_DIR="/home/$USERNAME/dotfiles"
if [ -d "$DOTFILES_DIR" ]; then
  echo "Dotfiles directory exists; pulling latest changes..."
  sudo -u "$USERNAME" git -C "$DOTFILES_DIR" pull
else
  sudo -u "$USERNAME" git clone https://github.com/ameistad/dotfiles "$DOTFILES_DIR"
fi
chown -R "$USERNAME:$USERNAME" "$DOTFILES_DIR"

# Create a symlink for .zshrc from the dotfiles repo
ZSHRC="/home/$USERNAME/.zshrc"
[ -e "$ZSHRC" ] && rm -f "$ZSHRC"
ln -s "$DOTFILES_DIR/.zshrc" "$ZSHRC"
chown -h "$USERNAME:$USERNAME" "$ZSHRC"

# Create .localrc with custom environment variables
LOCALRC="/home/$USERNAME/.localrc"
cat > "$LOCALRC" << 'EOF'
export ZSH=$HOME/dotfiles
export PROJECTS_DIRECTORY=$HOME
EOF
chown "$USERNAME:$USERNAME" "$LOCALRC"
chmod 644 "$LOCALRC"

echo "Setup complete. Please log out and log back in as $USERNAME to apply changes."
