#!/bin/sh

set -eu

REPO_URL="https://github.com/pabumake/dotfiles"
REPO_NAME="dotfiles"
DOTFILES_DIR="$HOME/$REPO_NAME"
STARSHIP_CONFIG="$HOME/.config/starship.toml"

is_stow_installed() {
  pacman -Qi "stow" >/dev/null 2>&1
}

if ! is_stow_installed; then
  echo "stow is required for dotfiles setup. Install stow first."
  exit 1
fi

if [ -d "$DOTFILES_DIR/.git" ]; then
  echo "Repository '$REPO_NAME' already exists. Skipping clone"
else
  echo "Cloning dotfiles repository into $DOTFILES_DIR"
  git clone "$REPO_URL" "$DOTFILES_DIR"
fi

if [ -e "$STARSHIP_CONFIG" ] || [ -L "$STARSHIP_CONFIG" ]; then
  echo "Removing existing starship config at $STARSHIP_CONFIG"
  rm -f "$STARSHIP_CONFIG"
else
  echo "No existing starship config found; skipping removal"
fi

cd "$DOTFILES_DIR"
echo "Applying stow package: starship"
stow starship
echo "Dotfiles setup complete"
