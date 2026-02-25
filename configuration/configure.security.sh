#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

LC_ALL=C
found=0

for script_path in "$SCRIPT_DIR"/configure.security.*.sh; do
  [ -e "$script_path" ] || continue

  script_name="$(basename -- "$script_path")"
  case "$script_name" in
    configure.security.sh|configure.security.app.*.sh)
      continue
      ;;
  esac

  found=1
  printf '[INFO] Running discovered security config script: %s\n' "$script_name"
  "$script_path"
done

if [ "$found" -eq 0 ]; then
  echo "[INFO] No discovered security config scripts found"
fi
