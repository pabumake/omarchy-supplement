#!/bin/sh

set -eu

# Call the Remote Install Script for OpenVPN Waybar Toggle
curl -fsSL https://raw.githubusercontent.com/pabumake/omarchy-openvpn-vpn-toggle/main/install.sh | bash

echo "OpenVPN Waybar Toggle setup complete"
