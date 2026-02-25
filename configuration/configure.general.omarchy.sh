#!/bin/sh

set -eu

HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.conf"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
OVERRIDES_CONFIG="$PROJECT_ROOT/cfg/hyprland-overrides.conf"
SOURCE_LINE="source = $OVERRIDES_CONFIG"

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

if [ ! -f "$HYPRLAND_CONFIG" ]; then
  echo "Hyprland config not found at $HYPRLAND_CONFIG"
  echo "Please install Hyprland first"
  exit 1
fi

if [ ! -f "$OVERRIDES_CONFIG" ]; then
  echo "Overrides config not found at $OVERRIDES_CONFIG"
  exit 1
fi

if grep -Fxq "$SOURCE_LINE" "$HYPRLAND_CONFIG"; then
  echo "Source line already exists in $HYPRLAND_CONFIG"
else
  echo "Adding source line to $HYPRLAND_CONFIG"
  run_cmd sh -c 'printf "\n%s\n" "$1" >> "$2"' sh "$SOURCE_LINE" "$HYPRLAND_CONFIG"
  echo "Source line added successfully"
fi

echo "Hyprland overrides setup complete"
