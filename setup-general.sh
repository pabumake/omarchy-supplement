#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

. "$PROJECT_ROOT/helper/setup.sh"

run_setup_from_entrypoint "$0" "$@"
