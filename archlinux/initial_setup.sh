#!/bin/bash
# curl -fsSL https://sh.ameistad.com/archlinux/initial_setup.sh | bash
set -e

# Must run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Echo to the user what this script does
echo "This script will perform the following actions:"
echo "1. Update system packages"
echo "2. Install essential packages"
echo "3. Create or update a user with sudo privileges"
echo "4. Set up the user's SSH key"
echo "5. Install dotfiles and set up zsh"

# Accept command line arguments or prompt
USERNAME="${1:-}"
NEW_HOSTNAME="${2:-}"

if [ -z "$USERNAME" ]; then
  read -p "Enter the username to create/update for first user: " USERNAME
fi

if [ -z "$USERNAME" ]; then
  echo "Username cannot be empty."
  exit 1
fi

if [ -z "$NEW_HOSTNAME" ]; then
  read -p "Enter hostname: " NEW_HOSTNAME
fi

if [ -z "$NEW_HOSTNAME" ]; then
  echo "Hostname cannot be empty."
  exit 1
fi

# Get current hostname from /etc/hostname or use hostnamectl
CURRENT_HOSTNAME=$(cat /etc/hostname 2>/dev/null || hostnamectl --static 2>/dev/null || echo "unknown")

# Change hostname using hostnamectl
hostnamectl set-hostname "$NEW_HOSTNAME"

# Update /etc/hostname
echo "$NEW_HOSTNAME" > /etc/hostname

# Update /etc/hosts: replace current hostname with new hostname
if [ "$CURRENT_HOSTNAME" != "unknown" ] && grep -q "$CURRENT_HOSTNAME " /etc/hosts; then
  sed -i "s/\b$CURRENT_HOSTNAME\b/$NEW_HOSTNAME/g" /etc/hosts
else
  echo "Warning: Could not find current hostname in /etc/hosts, adding new entry."
  echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
fi

echo "Hostname changed from '$CURRENT_HOSTNAME' to '$NEW_HOSTNAME'."

echo "Updating system packages..."
pacman -Syu --noconfirm

echo "Installing essential packages..."
pacman -S --noconfirm sudo neovim curl python python-pip git zsh openssh which base-devel nodejs npm

echo "Enabling SSH service..."
systemctl enable sshd
systemctl start sshd

echo "Setting up the user..."
if id "$USERNAME" &>/dev/null; then
  echo "User $USERNAME exists, skipping creation."
else
  useradd -m -G wheel -s /bin/zsh "$USERNAME"
  echo "Please set password for user $USERNAME:"
  passwd "$USERNAME"
fi

# Ensure user is in wheel group for sudo access
usermod -aG wheel "$USERNAME"

# Enable wheel group in sudoers if not already enabled
if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
  echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
fi

# Find zsh path - try common locations
ZSH_PATH=""
for path in /bin/zsh /usr/bin/zsh /usr/local/bin/zsh; do
  if [ -x "$path" ]; then
    ZSH_PATH="$path"
    break
  fi
done

if [ -z "$ZSH_PATH" ]; then
  echo "Error: zsh not found in standard locations"
  exit 1
fi

# Switch default shell to zsh for the user
usermod -s "$ZSH_PATH" "$USERNAME"

# Create .ssh directory with correct permissions
SSH_DIR="/home/$USERNAME/.ssh"
mkdir -p "$SSH_DIR"
chown "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Fetch the public key and store it as authorized_keys
curl -fsSL https://ameistad.com/pub_key.txt -o "$SSH_DIR/authorized_keys"
chown "$USERNAME:$USERNAME" "$SSH_DIR/authorized_keys"
chmod 600 "$SSH_DIR/authorized_keys"

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
export PROJECTS_DIRECTORY=$HOME
EOF
chown "$USERNAME:$USERNAME" "$LOCALRC"
chmod 644 "$LOCALRC"

echo "Setup complete. Please reboot."

