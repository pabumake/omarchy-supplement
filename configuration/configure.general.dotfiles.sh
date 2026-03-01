#!/bin/sh

set -eu

REPO_URL="https://github.com/pabumake/dotfiles"
REPO_NAME="dotfiles"
DOTFILES_DIR="$HOME/$REPO_NAME"
STARSHIP_CONFIG="$HOME/.config/starship.toml"
GH_MANAGER_CONFIG_DIR="$HOME/.config/gh-manager"

print_command() {
  printf '[DRY-RUN]'
  for arg in "$@"; do
    printf ' %s' "$arg"
  done
  printf '\n'
}

run_cmd() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    print_command "$@"
    return 0
  fi
  "$@"
}

is_stow_installed() {
  pacman -Qi "stow" >/dev/null 2>&1
}

remove_existing_path() {
  path="$1"
  label="$2"

  if [ -e "$path" ] || [ -L "$path" ]; then
    echo "Removing existing $label at $path"
    run_cmd rm -rf "$path"
  else
    echo "No existing $label found at $path; skipping removal"
  fi
}

stow_package_if_present() {
  package_name="$1"
  package_dir="$DOTFILES_DIR/$package_name"

  if [ ! -d "$package_dir" ]; then
    echo "Dotfiles package '$package_name' not found at $package_dir; skipping"
    return 0
  fi

  echo "Applying stow package: $package_name"
  run_cmd stow -d "$DOTFILES_DIR" -t "$HOME" "$package_name"
}

if ! is_stow_installed; then
  echo "stow is required for dotfiles setup. Install stow first."
  exit 1
fi

if [ -d "$DOTFILES_DIR/.git" ]; then
  echo "Repository '$REPO_NAME' already exists. Skipping clone"
else
  echo "Cloning dotfiles repository into $DOTFILES_DIR"
  run_cmd git clone "$REPO_URL" "$DOTFILES_DIR"
fi

remove_existing_path "$STARSHIP_CONFIG" "starship config"
remove_existing_path "$GH_MANAGER_CONFIG_DIR" "gh-manager config"

stow_package_if_present "starship"
stow_package_if_present "gh-manager"

echo "Dotfiles setup complete"
