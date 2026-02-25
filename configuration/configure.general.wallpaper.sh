#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

. "$PROJECT_ROOT/helper/common.sh"

WALLPAPER_URL="${WALLPAPER_URL:-https://raw.githubusercontent.com/pabumake/catpucchin-latte-wallpapers/main/wallpaper/catpucchin-dark-omarchy-label.jpg}"
WALLPAPER_DEST="${WALLPAPER_DEST:-$HOME/.config/omarchy/backgrounds/custom/catpucchin-dark-omarchy-label.jpg}"
WALLPAPER_FAIL_HARD="${WALLPAPER_FAIL_HARD:-0}"
CURRENT_LINK="$HOME/.config/omarchy/current/background"

download_wallpaper() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    if command -v curl >/dev/null 2>&1; then
      run_cmd curl -fsSL --retry 3 --retry-delay 2 -o "$WALLPAPER_DEST" "$WALLPAPER_URL"
    elif command -v wget >/dev/null 2>&1; then
      run_cmd wget -qO "$WALLPAPER_DEST" "$WALLPAPER_URL"
    else
      log_warn "Neither curl nor wget found during dry-run; showing curl command as placeholder."
      run_cmd curl -fsSL --retry 3 --retry-delay 2 -o "$WALLPAPER_DEST" "$WALLPAPER_URL"
    fi
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 2 -o "$WALLPAPER_DEST" "$WALLPAPER_URL"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$WALLPAPER_DEST" "$WALLPAPER_URL"
    return 0
  fi

  log_warn "Neither curl nor wget is available; cannot download wallpaper."
  return 1
}

handle_download_failure() {
  if [ "$WALLPAPER_FAIL_HARD" = "1" ]; then
    log_error "Wallpaper download failed and WALLPAPER_FAIL_HARD=1."
    return 1
  fi

  log_warn "Wallpaper download failed; continuing setup without changing wallpaper."
  return 0
}

refresh_wallpaper_best_effort() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    run_cmd pkill -x swaybg
    run_cmd sh -c 'setsid uwsm-app -- swaybg -i "$1" -m fill >/dev/null 2>&1 &' sh "$CURRENT_LINK"
    return 0
  fi

  if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
    return 0
  fi

  if ! command -v pkill >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v uwsm-app >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v swaybg >/dev/null 2>&1; then
    return 0
  fi

  run_cmd_best_effort pkill -x swaybg
  run_cmd_best_effort sh -c 'setsid uwsm-app -- swaybg -i "$1" -m fill >/dev/null 2>&1 &' sh "$CURRENT_LINK"
}

log_info "Applying general wallpaper configuration"

run_cmd mkdir -p "$(dirname -- "$WALLPAPER_DEST")"
run_cmd mkdir -p "$(dirname -- "$CURRENT_LINK")"

if [ -s "$WALLPAPER_DEST" ]; then
  log_info "Wallpaper already present at $WALLPAPER_DEST"
else
  log_info "Downloading default wallpaper from $WALLPAPER_URL"
  if ! download_wallpaper; then
    handle_download_failure || exit 1
    exit 0
  fi
fi

run_cmd ln -nsf "$WALLPAPER_DEST" "$CURRENT_LINK"
refresh_wallpaper_best_effort

log_info "General wallpaper configuration complete"
