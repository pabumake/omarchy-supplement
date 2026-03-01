#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_ROOT/helper/common.sh"
. "$PROJECT_ROOT/helper/installers.sh"

INSTALLER_MANIFEST="$PROJECT_ROOT/application/application.general.installers.txt"

log_info "Applying general custom installers"
install_manifest_custom_tools "$INSTALLER_MANIFEST"
log_info "General custom installers complete"
