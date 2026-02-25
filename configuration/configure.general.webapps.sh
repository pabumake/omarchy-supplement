#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_ROOT/helper/common.sh"
. "$PROJECT_ROOT/helper/webapps.sh"

WEBAPP_MANIFEST="$PROJECT_ROOT/application/application.general.webapps.txt"

log_info "Applying general webapp configuration"
install_profile_webapps "general" "$WEBAPP_MANIFEST"
log_info "General webapp configuration complete"
