#!/bin/sh

DEPRECATION_DATE="${DEPRECATION_DATE:-2026-12-31}"

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

deprecated_notice() {
  script_name="$1"
  replacement="$2"
  log_warn "$script_name is deprecated and will be removed after $DEPRECATION_DATE. Use $replacement."
}

print_command() {
  printf '[DRY-RUN]'
  for arg in "$@"; do
    printf ' %s' "$arg"
  done
  printf '\n'
}

run_cmd() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    print_command "$@"
    return 0
  fi
  "$@"
}

run_cmd_best_effort() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    print_command "$@"
    return 0
  fi
  if "$@"; then
    return 0
  fi
  log_warn "Command failed but continuing: $*"
  return 0
}

require_cmd() {
  cmd_name="$1"
  if ! command -v "$cmd_name" >/dev/null 2>&1; then
    log_error "Required command not found: $cmd_name"
    return 1
  fi
}

require_readable_file() {
  file_path="$1"
  if [ ! -r "$file_path" ]; then
    log_error "Required file is missing or unreadable: $file_path"
    return 1
  fi
}

preflight_arch_omarchy() {
  log_info "Running preflight checks"

  if [ ! -f /etc/arch-release ]; then
    log_error "This installer supports Arch/Omarchy only (/etc/arch-release not found)"
    return 1
  fi

  require_cmd pacman
  require_cmd yay
  require_cmd grep
  require_cmd awk
}
