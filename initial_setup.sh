#!/bin/bash

# Exit on any error
set -e

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Prompt for the username
read -p "Enter the username to create/update for first user: " USERNAME

echo "Updating system packages..."
apt update && apt upgrade -y

echo "Installing essential packages..."
apt install -y sudo vim curl python3 python3-pip git software-properties-common

echo "Installing Ansible..."
apt-add-repository --yes --update ppa:ansible/ansible
apt install -y ansible

echo "Setting up the first user..."
adduser "$USERNAME"  # Add the user
usermod -aG sudo "$USERNAME"  # Add the user to the sudo group

echo "Setup complete. Please log out and log back in as $USERNAME to apply changes."
