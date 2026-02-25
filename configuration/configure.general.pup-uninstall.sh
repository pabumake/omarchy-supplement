#!/bin/sh

set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PACKAGE_MANIFEST="${PACKAGE_MANIFEST:-$PROJECT_ROOT/application/application.general.pup-remove.packages.txt}"
WEBAPP_MANIFEST="${WEBAPP_MANIFEST:-$PROJECT_ROOT/application/application.general.pup-remove.webapps.txt}"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$DESKTOP_DIR/icons"
PACKAGES_REMOVED=0
PACKAGES_SKIPPED_NOT_INSTALLED=0
PACKAGES_FAILED=0
PACKAGES_UNRESOLVED_ORDER=0
WEBAPPS_REMOVED=0
WEBAPPS_SKIPPED_NOT_FOUND=0
WEBAPPS_SKIPPED_NOT_WRAPPER=0

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

normalize_dep_token() {
  printf '%s' "$1" | sed -E 's/[<>=].*$//'
}

package_depends_in_manifest() {
  package_name="$1"
  installed_file="$2"
  pacman -Qi "$package_name" 2>/dev/null | awk '
    /^Depends On[[:space:]]*:/ {
      capture = 1
      line = $0
      sub(/^[^:]*:[[:space:]]*/, "", line)
      print line
      next
    }
    capture && /^[[:space:]]/ {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      print line
      next
    }
    capture {
      capture = 0
    }
  ' | tr ' ' '\n' | while IFS= read -r dep_token; do
    [ -n "$dep_token" ] || continue
    [ "$dep_token" = "None" ] && continue
    dep_name="$(normalize_dep_token "$dep_token")"
    [ -n "$dep_name" ] || continue
    if grep -Fxq "$dep_name" "$installed_file"; then
      printf '%s\n' "$dep_name"
    fi
  done
}

build_installed_targets() {
  installed_file="$1"

  while IFS= read -r raw_line || [ -n "$raw_line" ]; do
    package_name="$(trim_line "$raw_line")"
    [ -n "$package_name" ] || continue

    if pacman -Q "$package_name" >/dev/null 2>&1; then
      printf '%s\n' "$package_name" >>"$installed_file"
    else
      log_info "Skipping package (not installed): $package_name"
      PACKAGES_SKIPPED_NOT_INSTALLED=$((PACKAGES_SKIPPED_NOT_INSTALLED + 1))
    fi
  done <"$PACKAGE_MANIFEST"
}

build_dependency_edges() {
  installed_file="$1"
  edges_file="$2"

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue

    package_depends_in_manifest "$package_name" "$installed_file" | while IFS= read -r dep_name || [ -n "$dep_name" ]; do
      [ -n "$dep_name" ] || continue
      printf '%s|%s\n' "$package_name" "$dep_name" >>"$edges_file"
    done
  done <"$installed_file"
}

plan_removal_order() {
  installed_file="$1"
  edges_file="$2"
  order_file="$3"
  unresolved_file="$4"

  remaining_file="$(mktemp "${TMPDIR:-/tmp}/pup-uninstall-remaining.XXXXXX")"
  removable_file="$(mktemp "${TMPDIR:-/tmp}/pup-uninstall-removable.XXXXXX")"
  next_remaining_file="$(mktemp "${TMPDIR:-/tmp}/pup-uninstall-next.XXXXXX")"

  cp "$installed_file" "$remaining_file"

  while [ -s "$remaining_file" ]; do
    awk -F'|' '
      NR == FNR {
        remaining[$0] = 1
        ordered[++n] = $0
        next
      }
      ($1 in remaining) && ($2 in remaining) {
        has_dependents[$2] = 1
      }
      END {
        for (i = 1; i <= n; i++) {
          pkg = ordered[i]
          if (!(pkg in has_dependents)) {
            print pkg
          }
        }
      }
    ' "$remaining_file" "$edges_file" >"$removable_file"

    if [ ! -s "$removable_file" ]; then
      sort "$remaining_file" >"$unresolved_file"
      cat "$unresolved_file" >>"$order_file"
      PACKAGES_UNRESOLVED_ORDER=$(wc -l <"$unresolved_file" | tr -d ' ')
      rm -f "$remaining_file" "$removable_file" "$next_remaining_file"
      break
    fi

    cat "$removable_file" >>"$order_file"
    grep -Fvx -f "$removable_file" "$remaining_file" >"$next_remaining_file" || true
    mv "$next_remaining_file" "$remaining_file"
  done

  rm -f "$remaining_file" "$removable_file" "$next_remaining_file"
}

remove_package_best_effort() {
  package_name="$1"
  log_info "Removing package: $package_name"

  if is_dry_run; then
    run_cmd sudo pacman -Rns --noconfirm "$package_name"
    PACKAGES_REMOVED=$((PACKAGES_REMOVED + 1))
    return 0
  fi

  if sudo pacman -Rns --noconfirm "$package_name"; then
    PACKAGES_REMOVED=$((PACKAGES_REMOVED + 1))
  else
    log_warn "Failed to remove package: $package_name"
    PACKAGES_FAILED=$((PACKAGES_FAILED + 1))
  fi
}

process_packages() {
  if [ ! -r "$PACKAGE_MANIFEST" ]; then
    log_warn "Package manifest not found: $PACKAGE_MANIFEST"
    return 0
  fi

  installed_file="$(mktemp "${TMPDIR:-/tmp}/pup-uninstall-installed.XXXXXX")"
  edges_file="$(mktemp "${TMPDIR:-/tmp}/pup-uninstall-edges.XXXXXX")"
  order_file="$(mktemp "${TMPDIR:-/tmp}/pup-uninstall-order.XXXXXX")"
  unresolved_file="$(mktemp "${TMPDIR:-/tmp}/pup-uninstall-unresolved.XXXXXX")"

  build_installed_targets "$installed_file"
  if [ ! -s "$installed_file" ]; then
    log_info "No installed packages matched pup remove manifest"
    rm -f "$installed_file" "$edges_file" "$order_file" "$unresolved_file"
    return 0
  fi

  build_dependency_edges "$installed_file" "$edges_file"
  plan_removal_order "$installed_file" "$edges_file" "$order_file" "$unresolved_file"

  package_order="$(tr '\n' ' ' <"$order_file" | sed -E 's/[[:space:]]+$//')"
  log_info "Package removal order: $package_order"
  if [ "$PACKAGES_UNRESOLVED_ORDER" -gt 0 ]; then
    unresolved_order="$(tr '\n' ' ' <"$unresolved_file" | sed -E 's/[[:space:]]+$//')"
    log_warn "Dependency ordering unresolved for $PACKAGES_UNRESOLVED_ORDER package(s); appended lexical fallback order: $unresolved_order"
  fi

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    remove_package_best_effort "$package_name"
  done <"$order_file"

  rm -f "$installed_file" "$edges_file" "$order_file" "$unresolved_file"
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
      WEBAPPS_SKIPPED_NOT_FOUND=$((WEBAPPS_SKIPPED_NOT_FOUND + 1))
      continue
    fi

    if ! is_omarchy_webapp_wrapper "$desktop_file"; then
      log_warn "Skipping webapp (not an Omarchy wrapper): $app_name"
      WEBAPPS_SKIPPED_NOT_WRAPPER=$((WEBAPPS_SKIPPED_NOT_WRAPPER + 1))
      continue
    fi

    log_info "Removing webapp wrapper: $app_name"
    run_cmd rm -f "$desktop_file"
    if [ -f "$icon_file" ]; then
      run_cmd rm -f "$icon_file"
    fi
    WEBAPPS_REMOVED=$((WEBAPPS_REMOVED + 1))
  done <"$WEBAPP_MANIFEST"
}

log_info "Applying Pup uninstall configuration"
process_packages
process_webapps
log_info "Pup uninstall summary: packages removed=$PACKAGES_REMOVED skipped_not_installed=$PACKAGES_SKIPPED_NOT_INSTALLED failed=$PACKAGES_FAILED unresolved_order=$PACKAGES_UNRESOLVED_ORDER; webapps removed=$WEBAPPS_REMOVED skipped_not_found=$WEBAPPS_SKIPPED_NOT_FOUND skipped_not_wrapper=$WEBAPPS_SKIPPED_NOT_WRAPPER"
log_info "Pup uninstall configuration complete"
