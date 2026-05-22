#!/usr/bin/env bash

# Run as root
# curl -fsSL https://sh.ameistad.com/debian_trixie/dotfiles_setup.sh | bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]:-}")"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
    source "$SCRIPT_DIR/common.sh"
else
    eval "$(curl -fsSL https://sh.ameistad.com/debian_trixie/common.sh)"
fi

require_root

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/ameistad/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-/root/dotfiles}"
ZSHRC="/root/.zshrc"
LOCALRC="/root/.localrc"
NVIM_CONFIG="/root/.config/nvim"

link_file() {
    local source="$1"
    local target="$2"

    if [[ -L "$target" || -f "$target" ]]; then
        rm -f "$target"
    elif [[ -e "$target" ]]; then
        print_warning "$target exists and is not a regular file or symlink; leaving it unchanged."
        return
    fi

    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
}

print_status "Installing dotfiles prerequisites..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y git zsh fzf

print_status "Setting root shell to zsh..."
usermod -s "$(command -v zsh)" root

if [[ -d "$DOTFILES_DIR/.git" ]]; then
    print_status "Dotfiles repository exists; pulling latest changes..."
    git -C "$DOTFILES_DIR" pull
elif [[ -e "$DOTFILES_DIR" ]]; then
    print_error "$DOTFILES_DIR exists but is not a git repository."
    exit 1
else
    print_status "Cloning dotfiles..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

chown -R root:root "$DOTFILES_DIR"

ZSHRC_SOURCE=""
for candidate in "$DOTFILES_DIR/zsh/.zshrc" "$DOTFILES_DIR/.zshrc"; do
    if [[ -f "$candidate" ]]; then
        ZSHRC_SOURCE="$candidate"
        break
    fi
done

if [[ -n "$ZSHRC_SOURCE" ]]; then
    print_status "Linking root .zshrc..."
    link_file "$ZSHRC_SOURCE" "$ZSHRC"
    chown -h root:root "$ZSHRC"
else
    print_warning "No .zshrc found at $DOTFILES_DIR/zsh/.zshrc or $DOTFILES_DIR/.zshrc; skipping .zshrc link."
fi

if [[ -d "$DOTFILES_DIR/nvim" ]]; then
    print_status "Linking root Neovim config..."
    link_file "$DOTFILES_DIR/nvim" "$NVIM_CONFIG"
    chown -h root:root "$NVIM_CONFIG"
else
    print_warning "$DOTFILES_DIR/nvim not found; skipping Neovim config link."
fi

print_status "Writing root .localrc..."
cat > "$LOCALRC" << 'EOF'
export PROJECTS_DIRECTORY=$HOME
EOF
chown root:root "$LOCALRC"
chmod 644 "$LOCALRC"

print_status "Root dotfiles setup complete."
