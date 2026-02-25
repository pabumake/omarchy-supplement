#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

"$SCRIPT_DIR/configure.general.dotfiles.sh"
"$SCRIPT_DIR/configure.general.omarchy.sh"
