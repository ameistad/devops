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
if [ -z "$USERNAME" ]; then
  echo "Username cannot be empty."
  exit 1
fi

echo "Updating system packages..."
apt update && apt upgrade -y

echo "Installing essential packages..."
apt install -y sudo vim curl python3 python3-pip git software-properties-common

echo "Installing Ansible..."
apt install -y ansible

echo "Setting up the first user..."
adduser "$USERNAME" || echo "User $USERNAME already exists."  # Add the user if it doesn't exist
usermod -aG sudo "$USERNAME"  # Add the user to the sudo group

echo "Setup complete. Please log out and log back in as $USERNAME to apply changes."
