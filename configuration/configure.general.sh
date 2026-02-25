#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

LC_ALL=C

for script_path in "$SCRIPT_DIR"/configure.general.*.sh; do
  [ -e "$script_path" ] || continue

  script_name="$(basename -- "$script_path")"
  case "$script_name" in
    configure.general.sh|configure.general.app.*.sh)
      continue
      ;;
  esac

  printf '[INFO] Running discovered general config script: %s\n' "$script_name"
  "$script_path"
done
