#!/bin/sh

resolve_omarchy_webapp_installer() {
  if command -v omarchy-webapp-install >/dev/null 2>&1; then
    command -v omarchy-webapp-install
    return 0
  fi

  fallback_path="$HOME/.local/share/omarchy/bin/omarchy-webapp-install"
  if [ -x "$fallback_path" ]; then
    printf '%s\n' "$fallback_path"
    return 0
  fi

  log_error "omarchy-webapp-install not found. Install Omarchy webapp tooling first."
  return 1
}

webapp_manifest_entries() {
  manifest_file="$1"

  awk '
    function trim(s) {
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }

    /^[[:space:]]*#/ { next }

    {
      line = trim($0)
      if (line == "") {
        next
      }

      count = split(line, parts, /\|/)
      if (count != 3) {
        printf "[ERROR] Invalid webapp manifest line (expected Name|URL|IconURL): %s\n", $0 > "/dev/stderr"
        exit 1
      }

      name = trim(parts[1])
      url = trim(parts[2])
      icon = trim(parts[3])

      if (name == "" || url == "" || icon == "") {
        printf "[ERROR] Invalid webapp manifest line (empty field): %s\n", $0 > "/dev/stderr"
        exit 1
      }

      printf "%s|%s|%s\n", name, url, icon
    }
  ' "$manifest_file"
}

resolve_edge_exec_path() {
  if [ -n "${EDGE_EXEC_PATH:-}" ]; then
    printf '%s\n' "$EDGE_EXEC_PATH"
    return 0
  fi

  for edge_desktop_path in \
    "$HOME/.local/share/applications"/microsoft-edge*.desktop \
    "$HOME/.nix-profile/share/applications"/microsoft-edge*.desktop \
    /usr/share/applications/microsoft-edge*.desktop; do
    [ -f "$edge_desktop_path" ] || continue

    edge_exec="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$edge_desktop_path" | head -n 1)"
    if [ -n "$edge_exec" ]; then
      EDGE_EXEC_PATH="$edge_exec"
      printf '%s\n' "$EDGE_EXEC_PATH"
      return 0
    fi
  done

  return 1
}

rewrite_desktop_exec() {
  desktop_file="$1"
  exec_line="$2"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-webapp-exec.XXXXXX")"

  awk -v replacement="$exec_line" '
    BEGIN { done = 0 }
    {
      if (!done && $0 ~ /^Exec=/) {
        print "Exec=" replacement
        done = 1
        next
      }
      print
    }
    END {
      if (!done) {
        print "Exec=" replacement
      }
    }
  ' "$desktop_file" >"$tmp_file"

  run_cmd mv "$tmp_file" "$desktop_file"
  run_cmd chmod +x "$desktop_file"
}

force_edge_exec_for_webapp() {
  app_name="$1"
  app_url="$2"
  webapp_desktop_file="$HOME/.local/share/applications/$app_name.desktop"
  edge_exec=""

  if resolve_edge_exec_path >/dev/null 2>&1; then
    edge_exec="$(resolve_edge_exec_path)"
  fi

  if [ -z "$edge_exec" ]; then
    if [ "${DRY_RUN:-0}" = "1" ]; then
      edge_exec="/usr/bin/microsoft-edge-stable"
      log_warn "Could not resolve Edge executable in dry-run; using placeholder: $edge_exec"
    else
      log_error "Microsoft Edge executable not found. Install microsoft-edge-stable-bin first."
      return 1
    fi
  fi

  exec_line="$edge_exec --app=$app_url"
  if [ "${DRY_RUN:-0}" = "1" ]; then
    print_command set-desktop-exec "$webapp_desktop_file" "$exec_line"
    return 0
  fi

  if [ ! -f "$webapp_desktop_file" ]; then
    log_error "Webapp desktop entry not found: $webapp_desktop_file"
    return 1
  fi

  rewrite_desktop_exec "$webapp_desktop_file" "$exec_line"
}

install_profile_webapps() {
  profile="$1"
  manifest_file="$2"

  require_readable_file "$manifest_file"
  installer="$(resolve_omarchy_webapp_installer)"
  entries="$(webapp_manifest_entries "$manifest_file")"

  if [ -z "$entries" ]; then
    log_info "No webapps found in $manifest_file"
    return 0
  fi

  printf '%s\n' "$entries" | while IFS='|' read -r app_name app_url icon_ref; do
    log_info "Installing webapp wrapper: $app_name"
    run_cmd "$installer" "$app_name" "$app_url" "$icon_ref"

    if [ "$profile" = "work" ]; then
      case "$app_name" in
        Word|Excel)
          log_info "Forcing Edge app-mode launcher for $app_name"
          force_edge_exec_for_webapp "$app_name" "$app_url"
          ;;
      esac
    fi
  done
}
