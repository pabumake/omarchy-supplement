#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

LC_ALL=C

pup_script="$SCRIPT_DIR/configure.general.pup-uninstall.sh"
if [ -e "$pup_script" ]; then
  if [ ! -r "$pup_script" ]; then
    printf '[ERROR] Pup uninstall script is not readable: %s\n' "$pup_script" >&2
    exit 1
  fi

  pup_name="$(basename -- "$pup_script")"
  printf '[INFO] Running discovered general config script: %s\n' "$pup_name"
  if [ -x "$pup_script" ]; then
    "$pup_script"
  else
    sh "$pup_script"
  fi
  printf '[INFO] Completed discovered general config script: %s\n' "$pup_name"
fi

for script_path in "$SCRIPT_DIR"/configure.general.*.sh; do
  [ -e "$script_path" ] || continue

  script_name="$(basename -- "$script_path")"
  case "$script_name" in
    configure.general.sh|configure.general.app.*.sh|configure.general.pup-uninstall.sh)
      continue
      ;;
  esac

  printf '[INFO] Running discovered general config script: %s\n' "$script_name"
  if [ -x "$script_path" ]; then
    "$script_path"
  else
    sh "$script_path"
  fi
  printf '[INFO] Completed discovered general config script: %s\n' "$script_name"
done
