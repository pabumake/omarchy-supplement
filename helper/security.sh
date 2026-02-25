#!/bin/sh

BLACKARCH_DOWNLOADS_URL="${BLACKARCH_DOWNLOADS_URL:-https://blackarch.org/downloads.html}"
BLACKARCH_STRAP_URL="${BLACKARCH_STRAP_URL:-https://blackarch.org/strap.sh}"
PACMAN_CONF_PATH="${PACMAN_CONF_PATH:-/etc/pacman.conf}"

blackarch_repo_configured() {
  if [ ! -r "$PACMAN_CONF_PATH" ]; then
    return 1
  fi
  grep -Eq '^[[:space:]]*\[blackarch\][[:space:]]*$' "$PACMAN_CONF_PATH"
}

extract_blackarch_strap_sha1() {
  curl -fsSL "$BLACKARCH_DOWNLOADS_URL" \
    | sed -nE 's/.*([a-fA-F0-9]{40}).*strap\.sh.*/\1/p' \
    | head -n 1
}

bootstrap_blackarch_repo() {
  if blackarch_repo_configured; then
    log_info "BlackArch repository already configured; skipping bootstrap"
    return 0
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    log_info "Dry-run: BlackArch repository is not configured; showing bootstrap commands"
    print_command curl -fsSL "$BLACKARCH_DOWNLOADS_URL"
    print_command curl -fsSL -o /tmp/blackarch-strap.sh "$BLACKARCH_STRAP_URL"
    print_command sha1sum /tmp/blackarch-strap.sh
    print_command sudo sh /tmp/blackarch-strap.sh
    print_command sudo pacman -Syy --noconfirm
    return 0
  fi

  tmp_dir="$(mktemp -d /tmp/blackarch-strap.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' EXIT INT TERM
  strap_path="$tmp_dir/strap.sh"

  log_info "Fetching BlackArch strap checksum from $BLACKARCH_DOWNLOADS_URL"
  expected_sha1="$(extract_blackarch_strap_sha1)"
  if [ -z "$expected_sha1" ]; then
    log_error "Failed to extract expected strap.sh SHA1 from $BLACKARCH_DOWNLOADS_URL"
    return 1
  fi

  log_info "Downloading BlackArch strap script from $BLACKARCH_STRAP_URL"
  run_cmd curl -fsSL -o "$strap_path" "$BLACKARCH_STRAP_URL"

  actual_sha1="$(sha1sum "$strap_path" | awk '{print $1}')"
  if [ "$actual_sha1" != "$expected_sha1" ]; then
    log_error "strap.sh checksum mismatch (expected=$expected_sha1 actual=$actual_sha1)"
    return 1
  fi

  log_info "strap.sh checksum verified; bootstrapping BlackArch repository"
  run_cmd sudo sh "$strap_path"
  run_cmd sudo pacman -Syy --noconfirm

  trap - EXIT INT TERM
  rm -rf "$tmp_dir"
}

security_prebootstrap_blackarch() {
  project_root="$1"
  bootstrap_script="$project_root/configuration/configure.security.blackarch.sh"

  require_readable_file "$bootstrap_script"
  log_info "Running security pre-bootstrap: BlackArch repository setup"

  if [ -x "$bootstrap_script" ]; then
    "$bootstrap_script"
  else
    sh "$bootstrap_script"
  fi
}
