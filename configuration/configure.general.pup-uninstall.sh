#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACKAGE_MANIFEST="${PACKAGE_MANIFEST:-$PROJECT_ROOT/cfg/pup-remove.packages.txt}"
WEBAPP_MANIFEST="${WEBAPP_MANIFEST:-$PROJECT_ROOT/cfg/pup-remove.webapps.txt}"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$DESKTOP_DIR/icons"

is_dry_run() {
  [ "${PUP_DRY_RUN:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

print_command() {
  printf '[DRY-RUN]'
  for arg in "$@"; do
    printf ' %s' "$arg"
  done
  printf '\n'
}

run_cmd() {
  if is_dry_run; then
    print_command "$@"
    return 0
  fi
  "$@"
}

trim_line() {
  printf '%s' "$1" | sed -E 's/[[:space:]]*#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

process_packages() {
  if [ ! -r "$PACKAGE_MANIFEST" ]; then
    log_warn "Package manifest not found: $PACKAGE_MANIFEST"
    return 0
  fi

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    package_name="$(trim_line "$raw_line")"
    [ -n "$package_name" ] || continue

    if pacman -Q "$package_name" >/dev/null 2>&1; then
      log_info "Removing package: $package_name"
      run_cmd sudo pacman -Rns --noconfirm "$package_name"
    else
      log_info "Skipping package (not installed): $package_name"
    fi
  done <"$PACKAGE_MANIFEST"
}

is_omarchy_webapp_wrapper() {
  desktop_file="$1"
  grep -Eq '^Exec=.*(omarchy-launch-webapp|omarchy-webapp-handler).*' "$desktop_file"
}

process_webapps() {
  if [ ! -r "$WEBAPP_MANIFEST" ]; then
    log_warn "Webapp manifest not found: $WEBAPP_MANIFEST"
    return 0
  fi

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    app_name="$(trim_line "$raw_line")"
    [ -n "$app_name" ] || continue

    desktop_file="$DESKTOP_DIR/$app_name.desktop"
    icon_file="$ICON_DIR/$app_name.png"

    if [ ! -f "$desktop_file" ]; then
      log_info "Skipping webapp (desktop not found): $app_name"
      continue
    fi

    if ! is_omarchy_webapp_wrapper "$desktop_file"; then
      log_warn "Skipping webapp (not an Omarchy wrapper): $app_name"
      continue
    fi

    log_info "Removing webapp wrapper: $app_name"
    run_cmd rm -f "$desktop_file"
    if [ -f "$icon_file" ]; then
      run_cmd rm -f "$icon_file"
    fi
  done <"$WEBAPP_MANIFEST"
}

log_info "Applying Pup uninstall configuration"
process_packages
process_webapps
log_info "Pup uninstall configuration complete"
