#!/bin/sh

set -eu

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

# Call the Remote Install Script for OpenVPN Waybar Toggle
run_cmd sh -c 'curl -fsSL https://raw.githubusercontent.com/pabumake/omarchy-openvpn-vpn-toggle/main/install.sh | bash'

echo "OpenVPN Waybar Toggle setup complete"
