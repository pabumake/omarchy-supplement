#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_ROOT/helper/common.sh"
. "$PROJECT_ROOT/helper/security.sh"

preflight_arch_omarchy
preflight_security_requirements
bootstrap_blackarch_repo
