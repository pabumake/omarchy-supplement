#!/bin/sh

manifest_packages() {
  manifest_file="$1"
  awk '
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      if (line != "") {
        print line
      }
    }
  ' "$manifest_file"
}

lookup_bundle_targets() {
  bundle_name="$1"
  bundles_file="$2"

  awk -v bundle="$bundle_name" '
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      if (line == "") {
        next
      }

      eq_index = index(line, "=")
      if (eq_index == 0) {
        next
      }

      key = substr(line, 1, eq_index - 1)
      value = substr(line, eq_index + 1)
      gsub(/^[[:space:]]+/, "", key)
      gsub(/[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)

      if (key == bundle) {
        print value
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$bundles_file"
}

resolve_security_targets() {
  manifest_file="$1"
  bundles_file="$2"

  require_readable_file "$bundles_file"

  expanded_tokens=""
  for token in $(manifest_packages "$manifest_file"); do
    case "$token" in
      bundle-*)
        bundle_values="$(lookup_bundle_targets "$token" "$bundles_file")" || {
          log_error "Unknown security bundle token: $token"
          return 1
        }

        if [ -z "$bundle_values" ]; then
          log_error "Security bundle token has no targets: $token"
          return 1
        fi

        for resolved in $bundle_values; do
          expanded_tokens="${expanded_tokens}
$resolved"
        done
        ;;
      blackarch-*)
        expanded_tokens="${expanded_tokens}
$token"
        ;;
      *)
        log_error "Unsupported token in security manifest: $token"
        log_error "Use blackarch-* groups or bundle-* aliases"
        return 1
        ;;
    esac
  done

  printf '%s\n' "$expanded_tokens" | awk 'NF > 0 && !seen[$0]++ { print $0 }'
}

install_security_group() {
  group_name="$1"
  log_info "Installing security group: $group_name"
  run_cmd sudo pacman -S --needed --noconfirm "$group_name"
}

default_provider_for_virtual_dep() {
  virtual_dep="$1"
  case "$virtual_dep" in
    tessdata)
      printf '%s\n' "tesseract-data-eng"
      ;;
    *)
      return 1
      ;;
  esac
}

extract_unresolved_virtual_dep() {
  log_file="$1"
  sed -n "s/.*unable to satisfy dependency '\([^']*\)' required by.*/\1/p" "$log_file" \
    | sed -E 's/[<>=].*$//' \
    | head -n 1
}

extract_provider_virtual_dep() {
  log_file="$1"
  sed -n 's/.*providers available for \([^:]*\):.*/\1/p' "$log_file" \
    | sed -E 's/[<>=].*$//' \
    | head -n 1
}

first_provider_from_log() {
  log_file="$1"
  awk '
    {
      for (i = 1; i < NF; i++) {
        if ($i ~ /^[0-9]+\)$/) {
          print $(i + 1)
          exit
        }
      }
    }
  ' "$log_file"
}

run_pacman_install_with_log() {
  log_file="$1"
  shift

  if sudo pacman -S --needed --noconfirm "$@" >"$log_file" 2>&1; then
    cat "$log_file"
    return 0
  fi

  cat "$log_file" >&2
  return 1
}

security_package_source_group() {
  package_name="$1"

  if [ -z "${SECURITY_PACKAGE_SOURCES_FILE:-}" ] || [ ! -r "${SECURITY_PACKAGE_SOURCES_FILE:-}" ]; then
    return 1
  fi

  awk -F'|' -v pkg="$package_name" '$1 == pkg { print $2; exit }' "$SECURITY_PACKAGE_SOURCES_FILE"
}

install_security_single_package_best_effort() {
  package_name="$1"
  source_group="$(security_package_source_group "$package_name" || true)"

  if pacman -Q "$package_name" >/dev/null 2>&1; then
    log_info "Skipping security package (already installed): $package_name"
    SEC_PACKAGES_ALREADY_INSTALLED=$((SEC_PACKAGES_ALREADY_INSTALLED + 1))
    return 0
  fi

  if [ -n "$source_group" ]; then
    log_info "Installing security package: $package_name (source group: $source_group)"
  else
    log_info "Installing security package: $package_name"
  fi

  if [ "${DRY_RUN:-0}" = "1" ]; then
    print_command sudo pacman -S --needed --noconfirm "$package_name"
    SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + 1))
    return 0
  fi

  pkg_log="$(mktemp "${TMPDIR:-/tmp}/security-pkg-install.XXXXXX")"
  if run_pacman_install_with_log "$pkg_log" "$package_name"; then
    SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + 1))
    rm -f "$pkg_log"
    return 0
  fi

  virtual_dep="$(extract_unresolved_virtual_dep "$pkg_log")"
  if [ -z "$virtual_dep" ]; then
    virtual_dep="$(extract_provider_virtual_dep "$pkg_log")"
  fi

  provider_pkg=""
  if [ -n "$virtual_dep" ]; then
    if provider_pkg="$(default_provider_for_virtual_dep "$virtual_dep" 2>/dev/null)"; then
      :
    else
      provider_pkg="$(first_provider_from_log "$pkg_log" || true)"
    fi
  fi

  if [ -n "$provider_pkg" ]; then
    log_warn "Retrying $package_name after installing provider '$provider_pkg' for virtual dependency '$virtual_dep'"
    SEC_RETRY_COUNT=$((SEC_RETRY_COUNT + 1))

    retry_log="$(mktemp "${TMPDIR:-/tmp}/security-provider-install.XXXXXX")"
    if run_pacman_install_with_log "$retry_log" "$provider_pkg"; then
      :
    else
      log_warn "Provider install failed for $provider_pkg; continuing with package retry"
    fi
    rm -f "$retry_log"

    retry_pkg_log="$(mktemp "${TMPDIR:-/tmp}/security-pkg-retry.XXXXXX")"
    if run_pacman_install_with_log "$retry_pkg_log" "$package_name"; then
      SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + 1))
      rm -f "$pkg_log" "$retry_pkg_log"
      return 0
    fi
    rm -f "$retry_pkg_log"
  fi

  log_warn "Skipping unrecoverable security package: $package_name"
  SEC_PACKAGES_FAILED=$((SEC_PACKAGES_FAILED + 1))
  printf '%s\n' "$package_name" >>"$SEC_FAILED_PACKAGES_FILE"
  rm -f "$pkg_log"
  return 0
}

install_security_chunk_file() {
  chunk_file="$1"
  chunk_count="$(awk 'END { print NR + 0 }' "$chunk_file")"
  [ "$chunk_count" -gt 0 ] || return 0

  package_args="$(tr '\n' ' ' <"$chunk_file" | sed -E 's/[[:space:]]+$//')"
  [ -n "$package_args" ] || return 0

  if [ "${DRY_RUN:-0}" = "1" ]; then
    print_command sudo pacman -S --needed --noconfirm $package_args
    SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + chunk_count))
    return 0
  fi

  chunk_log="$(mktemp "${TMPDIR:-/tmp}/security-chunk-install.XXXXXX")"
  # shellcheck disable=SC2086
  if run_pacman_install_with_log "$chunk_log" $package_args; then
    SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + chunk_count))
    rm -f "$chunk_log"
    return 0
  fi

  rm -f "$chunk_log"
  return 1
}

install_security_packages_bisect() {
  package_file="$1"
  pkg_count="$(awk 'END { print NR + 0 }' "$package_file")"
  [ "$pkg_count" -gt 0 ] || return 0

  if [ "$pkg_count" -eq 1 ]; then
    package_name="$(cat "$package_file")"
    install_security_single_package_best_effort "$package_name"
    return 0
  fi

  mid=$((pkg_count / 2))
  first_half="$(mktemp "${TMPDIR:-/tmp}/security-half-a.XXXXXX")"
  second_half="$(mktemp "${TMPDIR:-/tmp}/security-half-b.XXXXXX")"

  awk -v m="$mid" 'NR <= m { print }' "$package_file" >"$first_half"
  awk -v m="$mid" 'NR > m { print }' "$package_file" >"$second_half"

  if [ -s "$first_half" ]; then
    if ! install_security_chunk_file "$first_half"; then
      install_security_packages_bisect "$first_half"
    fi
  fi

  if [ -s "$second_half" ]; then
    if ! install_security_chunk_file "$second_half"; then
      install_security_packages_bisect "$second_half"
    fi
  fi

  rm -f "$first_half" "$second_half"
}

resolve_security_packages_from_groups() {
  groups_file="$1"
  output_packages_file="$2"

  raw_sources_file="$(mktemp "${TMPDIR:-/tmp}/security-group-sources-raw.XXXXXX")"
  dedup_sources_file="$(mktemp "${TMPDIR:-/tmp}/security-group-sources-dedup.XXXXXX")"

  while IFS= read -r group_name || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    log_info "Resolving security group members: $group_name"
    group_members_file="$(mktemp "${TMPDIR:-/tmp}/security-group-members.XXXXXX")"
    if pacman -Sg "$group_name" >"$group_members_file" 2>/dev/null; then
      awk -v grp="$group_name" '{ print $2 "|" grp }' "$group_members_file" >>"$raw_sources_file"
    else
      log_warn "Skipping unknown or unavailable security group: $group_name"
      SEC_GROUPS_MISSING=$((SEC_GROUPS_MISSING + 1))
    fi
    rm -f "$group_members_file"
  done <"$groups_file"

  if [ ! -s "$raw_sources_file" ]; then
    rm -f "$raw_sources_file" "$dedup_sources_file"
    return 0
  fi

  awk -F'|' '!seen[$1]++ { print $0 }' "$raw_sources_file" >"$dedup_sources_file"
  cut -d'|' -f1 "$dedup_sources_file" >"$output_packages_file"

  SECURITY_PACKAGE_SOURCES_FILE="$dedup_sources_file"
  rm -f "$raw_sources_file"
}

install_security_packages() {
  groups_file="$1"

  resolved_packages_file="$(mktemp "${TMPDIR:-/tmp}/security-resolved-packages.XXXXXX")"
  pending_packages_file="$(mktemp "${TMPDIR:-/tmp}/security-pending-packages.XXXXXX")"
  SEC_FAILED_PACKAGES_FILE="$(mktemp "${TMPDIR:-/tmp}/security-failed-packages.XXXXXX")"
  SECURITY_PACKAGE_SOURCES_FILE=""
  export SEC_FAILED_PACKAGES_FILE SECURITY_PACKAGE_SOURCES_FILE

  resolve_security_packages_from_groups "$groups_file" "$resolved_packages_file"
  SEC_GROUPS_RESOLVED="$(awk 'END { print NR + 0 }' "$groups_file")"
  SEC_GROUPS_MISSING="${SEC_GROUPS_MISSING:-0}"
  SEC_PACKAGES_TOTAL="$(awk 'END { print NR + 0 }' "$resolved_packages_file")"

  if [ "$SEC_PACKAGES_TOTAL" -eq 0 ]; then
    log_warn "No packages resolved from security groups"
    rm -f "$resolved_packages_file" "$pending_packages_file" "$SEC_FAILED_PACKAGES_FILE"
    if [ -n "${SECURITY_PACKAGE_SOURCES_FILE:-}" ]; then
      rm -f "$SECURITY_PACKAGE_SOURCES_FILE"
    fi
    return 0
  fi

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    if pacman -Q "$package_name" >/dev/null 2>&1; then
      SEC_PACKAGES_ALREADY_INSTALLED=$((SEC_PACKAGES_ALREADY_INSTALLED + 1))
    else
      printf '%s\n' "$package_name" >>"$pending_packages_file"
    fi
  done <"$resolved_packages_file"

  if [ -s "$pending_packages_file" ]; then
    chunk_size="${SECURITY_INSTALL_CHUNK_SIZE:-50}"
    current_chunk_file="$(mktemp "${TMPDIR:-/tmp}/security-chunk.XXXXXX")"
    count_in_chunk=0

    while IFS= read -r package_name || [ -n "$package_name" ]; do
      [ -n "$package_name" ] || continue
      printf '%s\n' "$package_name" >>"$current_chunk_file"
      count_in_chunk=$((count_in_chunk + 1))

      if [ "$count_in_chunk" -ge "$chunk_size" ]; then
        if ! install_security_chunk_file "$current_chunk_file"; then
          install_security_packages_bisect "$current_chunk_file"
        fi
        : >"$current_chunk_file"
        count_in_chunk=0
      fi
    done <"$pending_packages_file"

    if [ "$count_in_chunk" -gt 0 ]; then
      if ! install_security_chunk_file "$current_chunk_file"; then
        install_security_packages_bisect "$current_chunk_file"
      fi
    fi

    rm -f "$current_chunk_file"
  fi

  log_info "Security install summary: groups_resolved=$SEC_GROUPS_RESOLVED groups_missing=$SEC_GROUPS_MISSING packages_total=$SEC_PACKAGES_TOTAL already_installed=$SEC_PACKAGES_ALREADY_INSTALLED installed=$SEC_PACKAGES_INSTALLED failed=$SEC_PACKAGES_FAILED retries=$SEC_RETRY_COUNT"
  if [ -s "$SEC_FAILED_PACKAGES_FILE" ]; then
    failed_list="$(tr '\n' ' ' <"$SEC_FAILED_PACKAGES_FILE" | sed -E 's/[[:space:]]+$//')"
    log_warn "Security packages skipped after retries: $failed_list"
  fi

  rm -f "$resolved_packages_file" "$pending_packages_file" "$SEC_FAILED_PACKAGES_FILE"
  if [ -n "${SECURITY_PACKAGE_SOURCES_FILE:-}" ]; then
    rm -f "$SECURITY_PACKAGE_SOURCES_FILE"
  fi
}

install_single_package() {
  package_name="$1"
  log_info "Installing package: $package_name"
  run_cmd yay -S --noconfirm --needed "$package_name"
}

install_profile_applications() {
  profile="$1"
  manifest_file="$2"

  require_readable_file "$manifest_file"
  log_info "Installing applications for profile '$profile' from $manifest_file"

  if [ "$profile" = "security" ]; then
    bundles_file="$PROJECT_ROOT/cfg/blackarch-bundles.conf"
    install_mode="${SECURITY_INSTALL_MODE:-expand-groups}"
    targets="$(resolve_security_targets "$manifest_file" "$bundles_file")"
    if [ -z "$targets" ]; then
      log_warn "No security groups found in $manifest_file"
      return 0
    fi

    log_info "Resolved security install targets:"
    security_targets_file="$(mktemp "${TMPDIR:-/tmp}/security-targets.XXXXXX")"
    for target in $targets; do
      log_info "  - $target"
      printf '%s\n' "$target" >>"$security_targets_file"
    done

    SEC_GROUPS_RESOLVED=0
    SEC_GROUPS_MISSING=0
    SEC_PACKAGES_TOTAL=0
    SEC_PACKAGES_ALREADY_INSTALLED=0
    SEC_PACKAGES_INSTALLED=0
    SEC_PACKAGES_FAILED=0
    SEC_RETRY_COUNT=0
    export SEC_GROUPS_RESOLVED SEC_GROUPS_MISSING SEC_PACKAGES_TOTAL SEC_PACKAGES_ALREADY_INSTALLED
    export SEC_PACKAGES_INSTALLED SEC_PACKAGES_FAILED SEC_RETRY_COUNT

    case "$install_mode" in
      expand-groups)
        install_security_packages "$security_targets_file"
        ;;
      legacy-groups)
        log_warn "Using legacy security install mode (group installs may be interactive): $install_mode"
        while IFS= read -r target || [ -n "$target" ]; do
          [ -n "$target" ] || continue
          install_security_group "$target"
        done <"$security_targets_file"
        ;;
      *)
        log_error "Unsupported SECURITY_INSTALL_MODE: $install_mode"
        rm -f "$security_targets_file"
        return 1
        ;;
    esac

    rm -f "$security_targets_file"
    if [ "$SEC_PACKAGES_FAILED" -gt 0 ]; then
      log_warn "Security profile completed with package-level warnings"
    fi
    return 0
  fi

  packages="$(manifest_packages "$manifest_file")"
  if [ -z "$packages" ]; then
    log_warn "No packages found in $manifest_file"
    return 0
  fi

  for package_name in $packages; do
    install_single_package "$package_name"
  done
}
