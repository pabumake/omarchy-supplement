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

default_install_state_file() {
  if [ -n "${STATE_FILE:-}" ]; then
    printf '%s\n' "$STATE_FILE"
    return 0
  fi

  state_base="${XDG_STATE_HOME:-$HOME/.local/state}"
  printf '%s\n' "$state_base/omarchy-supplement/install-state.tsv"
}

ensure_install_state_ready() {
  state_file="$(default_install_state_file)"
  state_dir="$(dirname -- "$state_file")"
  mkdir -p "$state_dir"
  if [ ! -f "$state_file" ]; then
    : >"$state_file"
  fi
}

state_timestamp_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

state_upsert_package() {
  package_name="$1"
  profile="$2"
  preset="$3"
  source_manifest="$4"
  status="$5"

  ensure_install_state_ready
  state_file="$(default_install_state_file)"
  timestamp="$(state_timestamp_utc)"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-state-upsert.XXXXXX")"

  awk -F'\t' -v pkg="$package_name" -v prof="$profile" -v pre="$preset" '
    BEGIN { OFS="\t" }
    !($1 == pkg && $2 == prof && $3 == pre) { print $0 }
  ' "$state_file" >"$tmp_file"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$package_name" "$profile" "$preset" "$timestamp" "$source_manifest" "$status" >>"$tmp_file"
  run_cmd mv "$tmp_file" "$state_file"
}

state_mark_installed_package() {
  package_name="$1"
  state_upsert_package "$package_name" "${INSTALL_STATE_PROFILE:-unknown}" "${INSTALL_STATE_PRESET:--}" "${INSTALL_STATE_MANIFEST:-unknown}" "installed"
}

state_mark_imported_package() {
  package_name="$1"
  profile="$2"
  preset="$3"
  source_manifest="$4"
  state_upsert_package "$package_name" "$profile" "$preset" "$source_manifest" "imported"
}

state_mark_removed_package() {
  package_name="$1"
  profile="$2"
  preset="$3"
  source_manifest="$4"
  state_upsert_package "$package_name" "$profile" "$preset" "$source_manifest" "removed"
}

state_tracked_packages_for_scope() {
  profile="$1"
  preset="$2"
  output_file="$3"

  state_file="$(default_install_state_file)"
  if [ ! -r "$state_file" ]; then
    : >"$output_file"
    return 0
  fi
  awk -F'\t' -v prof="$profile" -v pre="$preset" '
    $2 == prof && $3 == pre && ($6 == "installed" || $6 == "imported") {
      print $1
    }
  ' "$state_file" | awk 'NF > 0 && !seen[$0]++ { print $0 }' >"$output_file"
}

normalize_dep_token() {
  printf '%s' "$1" | sed -E 's/[<>=].*$//'
}

package_depends_in_list() {
  package_name="$1"
  package_list_file="$2"

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
    if grep -Fxq "$dep_name" "$package_list_file"; then
      printf '%s\n' "$dep_name"
    fi
  done
}

build_uninstall_dependency_edges() {
  package_list_file="$1"
  edges_file="$2"

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    package_depends_in_list "$package_name" "$package_list_file" | while IFS= read -r dep_name || [ -n "$dep_name" ]; do
      [ -n "$dep_name" ] || continue
      printf '%s|%s\n' "$package_name" "$dep_name" >>"$edges_file"
    done
  done <"$package_list_file"
}

plan_uninstall_order() {
  package_list_file="$1"
  edges_file="$2"
  order_file="$3"
  unresolved_file="$4"

  remaining_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-remaining.XXXXXX")"
  removable_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-removable.XXXXXX")"
  next_remaining_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-next.XXXXXX")"

  cp "$package_list_file" "$remaining_file"

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
      break
    fi

    cat "$removable_file" >>"$order_file"
    grep -Fvx -f "$removable_file" "$remaining_file" >"$next_remaining_file" || true
    mv "$next_remaining_file" "$remaining_file"
  done

  rm -f "$remaining_file" "$removable_file" "$next_remaining_file"
}

resolve_profile_concrete_packages() {
  profile="$1"
  manifest_file="$2"
  output_file="$3"

  if [ "$profile" = "security" ]; then
    bundles_file="$PROJECT_ROOT/cfg/blackarch-bundles.conf"
    targets="$(resolve_security_targets "$manifest_file" "$bundles_file")"
    if [ -z "$targets" ]; then
      : >"$output_file"
      return 0
    fi

    targets_file="$(mktemp "${TMPDIR:-/tmp}/security-uninstall-targets.XXXXXX")"
    while IFS= read -r target || [ -n "$target" ]; do
      [ -n "$target" ] || continue
      printf '%s\n' "$target" >>"$targets_file"
    done <<EOF
$targets
EOF
    SEC_GROUPS_MISSING=0
    resolve_security_packages_from_groups "$targets_file" "$output_file"
    rm -f "$targets_file"
    return 0
  fi

  manifest_packages "$manifest_file" | awk 'NF > 0 && !seen[$0]++ { print $0 }' >"$output_file"
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

run_pacman_install_streaming() {
  log_file="$1"
  label="$2"
  shift
  shift

  log_info "$label: starting"
  if [ "${SECURITY_SUDO_NOTICE_SHOWN:-0}" -eq 0 ]; then
    log_info "Security install may prompt once for sudo password; package output will continue immediately after authentication."
    SECURITY_SUDO_NOTICE_SHOWN=1
  fi

  fifo_path="$(mktemp "${TMPDIR:-/tmp}/security-pacman-fifo.XXXXXX")"
  exit_file="$(mktemp "${TMPDIR:-/tmp}/security-pacman-exit.XXXXXX")"
  rm -f "$fifo_path"
  mkfifo "$fifo_path"

  (
    sudo pacman -S --needed --noconfirm "$@"
    printf '%s\n' "$?" >"$exit_file"
  ) >"$fifo_path" 2>&1 &
  pacman_pid=$!

  tee "$log_file" <"$fifo_path"
  wait "$pacman_pid" 2>/dev/null || true

  exit_code="$(cat "$exit_file" 2>/dev/null || printf '1')"
  rm -f "$fifo_path" "$exit_file"

  if [ "$exit_code" -eq 0 ]; then
    return 0
  fi

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
  if run_pacman_install_streaming "$pkg_log" "security package $package_name" "$package_name"; then
    SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + 1))
    state_mark_installed_package "$package_name"
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
    if run_pacman_install_streaming "$retry_log" "provider install $provider_pkg" "$provider_pkg"; then
      :
    else
      log_warn "Provider install failed for $provider_pkg; continuing with package retry"
    fi
    rm -f "$retry_log"

    retry_pkg_log="$(mktemp "${TMPDIR:-/tmp}/security-pkg-retry.XXXXXX")"
    if run_pacman_install_streaming "$retry_pkg_log" "security package retry $package_name" "$package_name"; then
      SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + 1))
      state_mark_installed_package "$package_name"
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
  chunk_label="${2:-security chunk}"
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
  if run_pacman_install_streaming "$chunk_log" "$chunk_label" $package_args; then
    SEC_PACKAGES_INSTALLED=$((SEC_PACKAGES_INSTALLED + chunk_count))
    while IFS= read -r package_name || [ -n "$package_name" ]; do
      [ -n "$package_name" ] || continue
      state_mark_installed_package "$package_name"
    done <"$chunk_file"
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
  total_groups="$(awk 'END { print NR + 0 }' "$groups_file")"
  current_group=0

  log_info "Resolving BlackArch group members ($total_groups groups). This can take a few minutes depending on mirror/network speed."

  while IFS= read -r group_name || [ -n "$group_name" ]; do
    [ -n "$group_name" ] || continue
    current_group=$((current_group + 1))
    log_info "Resolving security group members [$current_group/$total_groups]: $group_name"
    group_members_file="$(mktemp "${TMPDIR:-/tmp}/security-group-members.XXXXXX")"
    if pacman -Sg "$group_name" >"$group_members_file" 2>/dev/null; then
      group_member_count="$(awk 'END { print NR + 0 }' "$group_members_file")"
      log_info "Resolved group [$current_group/$total_groups]: $group_name ($group_member_count members)"
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

  raw_package_count="$(awk 'END { print NR + 0 }' "$raw_sources_file")"
  log_info "Finished group resolution: collected $raw_package_count raw package entries before deduplication"
  awk -F'|' '!seen[$1]++ { print $0 }' "$raw_sources_file" >"$dedup_sources_file"
  cut -d'|' -f1 "$dedup_sources_file" >"$output_packages_file"
  dedup_package_count="$(awk 'END { print NR + 0 }' "$output_packages_file")"
  log_info "Deduplicated security package set: $dedup_package_count packages"

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

  log_info "Checking already installed status for $SEC_PACKAGES_TOTAL security packages"
  checked_count=0
  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    checked_count=$((checked_count + 1))
    if pacman -Q "$package_name" >/dev/null 2>&1; then
      SEC_PACKAGES_ALREADY_INSTALLED=$((SEC_PACKAGES_ALREADY_INSTALLED + 1))
    else
      printf '%s\n' "$package_name" >>"$pending_packages_file"
    fi
    if [ $((checked_count % 25)) -eq 0 ]; then
      log_info "Installed-status progress: $checked_count/$SEC_PACKAGES_TOTAL checked"
    fi
  done <"$resolved_packages_file"

  pending_count="$(awk 'END { print NR + 0 }' "$pending_packages_file")"
  log_info "Security package install plan: pending=$pending_count already_installed=$SEC_PACKAGES_ALREADY_INSTALLED"

  if [ -s "$pending_packages_file" ]; then
    chunk_size="${SECURITY_INSTALL_CHUNK_SIZE:-50}"
    total_chunks=$(( (pending_count + chunk_size - 1) / chunk_size ))
    current_chunk=0
    current_chunk_file="$(mktemp "${TMPDIR:-/tmp}/security-chunk.XXXXXX")"
    count_in_chunk=0

    while IFS= read -r package_name || [ -n "$package_name" ]; do
      [ -n "$package_name" ] || continue
      printf '%s\n' "$package_name" >>"$current_chunk_file"
      count_in_chunk=$((count_in_chunk + 1))

      if [ "$count_in_chunk" -ge "$chunk_size" ]; then
        current_chunk=$((current_chunk + 1))
        log_info "Installing security package chunk [$current_chunk/$total_chunks] ($count_in_chunk packages)"
        if ! install_security_chunk_file "$current_chunk_file" "security chunk [$current_chunk/$total_chunks]"; then
          install_security_packages_bisect "$current_chunk_file"
        fi
        : >"$current_chunk_file"
        count_in_chunk=0
      fi
    done <"$pending_packages_file"

    if [ "$count_in_chunk" -gt 0 ]; then
      current_chunk=$((current_chunk + 1))
      log_info "Installing security package chunk [$current_chunk/$total_chunks] ($count_in_chunk packages)"
      if ! install_security_chunk_file "$current_chunk_file" "security chunk [$current_chunk/$total_chunks]"; then
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

import_profile_install_state() {
  profile="$1"
  manifest_file="$2"
  preset="$3"

  resolved_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-import-resolved.XXXXXX")"
  imported_count=0
  skipped_not_installed=0
  checked_count=0

  resolve_profile_concrete_packages "$profile" "$manifest_file" "$resolved_file"
  candidates_count="$(awk 'END { print NR + 0 }' "$resolved_file")"

  log_info "Importing current installed package state for profile '$profile' (preset='$preset')"
  log_info "Import candidates from manifest: $candidates_count"

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    checked_count=$((checked_count + 1))
    if pacman -Q "$package_name" >/dev/null 2>&1; then
      if [ "${DRY_RUN:-0}" = "0" ]; then
        state_mark_imported_package "$package_name" "$profile" "$preset" "$manifest_file"
      fi
      imported_count=$((imported_count + 1))
    else
      skipped_not_installed=$((skipped_not_installed + 1))
    fi
    if [ $((checked_count % 25)) -eq 0 ]; then
      log_info "Import progress: $checked_count/$candidates_count checked"
    fi
  done <"$resolved_file"

  rm -f "$resolved_file"
  log_info "Import summary: imported=$imported_count skipped_not_installed=$skipped_not_installed"
}

uninstall_profile_applications() {
  profile="$1"
  manifest_file="$2"
  preset="$3"

  resolved_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-resolved.XXXXXX")"
  tracked_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-tracked.XXXXXX")"
  selected_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-selected.XXXXXX")"
  installed_selected_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-installed-selected.XXXXXX")"
  edges_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-edges.XXXXXX")"
  order_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-order.XXXXXX")"
  unresolved_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-uninstall-unresolved.XXXXXX")"

  uninstall_candidates=0
  uninstall_tracked_matches=0
  uninstall_removed=0
  uninstall_skipped_not_installed=0
  uninstall_failed=0
  uninstall_unresolved_order=0

  resolve_profile_concrete_packages "$profile" "$manifest_file" "$resolved_file"
  state_tracked_packages_for_scope "$profile" "$preset" "$tracked_file"

  uninstall_candidates="$(awk 'END { print NR + 0 }' "$resolved_file")"
  uninstall_tracked_total="$(awk 'END { print NR + 0 }' "$tracked_file")"

  if [ -s "$tracked_file" ]; then
    grep -Fxf "$tracked_file" "$resolved_file" | awk 'NF > 0 && !seen[$0]++ { print $0 }' >"$selected_file" || true
  else
    : >"$selected_file"
  fi
  uninstall_tracked_matches="$(awk 'END { print NR + 0 }' "$selected_file")"

  log_info "Uninstall selection for profile '$profile' (preset='$preset')"
  log_info "Uninstall candidates=$uninstall_candidates tracked_scope=$uninstall_tracked_total tracked_matches=$uninstall_tracked_matches"

  if [ "$uninstall_tracked_matches" -eq 0 ]; then
    log_warn "No tracked packages matched selected manifest scope; nothing to uninstall."
    rm -f "$resolved_file" "$tracked_file" "$selected_file" "$installed_selected_file" "$edges_file" "$order_file" "$unresolved_file"
    return 0
  fi

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    if pacman -Q "$package_name" >/dev/null 2>&1; then
      printf '%s\n' "$package_name" >>"$installed_selected_file"
    else
      uninstall_skipped_not_installed=$((uninstall_skipped_not_installed + 1))
    fi
  done <"$selected_file"

  if [ ! -s "$installed_selected_file" ]; then
    log_info "All tracked packages are already absent; nothing to remove."
    rm -f "$resolved_file" "$tracked_file" "$selected_file" "$installed_selected_file" "$edges_file" "$order_file" "$unresolved_file"
    log_info "Uninstall summary: candidates=$uninstall_candidates tracked_matches=$uninstall_tracked_matches removed=$uninstall_removed skipped_not_installed=$uninstall_skipped_not_installed failed=$uninstall_failed unresolved_order=$uninstall_unresolved_order"
    return 0
  fi

  build_uninstall_dependency_edges "$installed_selected_file" "$edges_file"
  plan_uninstall_order "$installed_selected_file" "$edges_file" "$order_file" "$unresolved_file"
  if [ -s "$unresolved_file" ]; then
    uninstall_unresolved_order="$(awk 'END { print NR + 0 }' "$unresolved_file")"
  fi

  order_display="$(tr '\n' ' ' <"$order_file" | sed -E 's/[[:space:]]+$//')"
  log_info "Uninstall order: $order_display"
  if [ "$uninstall_unresolved_order" -gt 0 ]; then
    unresolved_display="$(tr '\n' ' ' <"$unresolved_file" | sed -E 's/[[:space:]]+$//')"
    log_warn "Dependency ordering unresolved for $uninstall_unresolved_order package(s); lexical fallback used: $unresolved_display"
  fi

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    log_info "Removing tracked package: $package_name"
    if [ "${DRY_RUN:-0}" = "1" ]; then
      print_command sudo pacman -Rns --noconfirm "$package_name"
      uninstall_removed=$((uninstall_removed + 1))
      continue
    fi

    if sudo pacman -Rns --noconfirm "$package_name"; then
      uninstall_removed=$((uninstall_removed + 1))
      state_mark_removed_package "$package_name" "$profile" "$preset" "$manifest_file"
    else
      log_warn "Failed to remove tracked package: $package_name"
      uninstall_failed=$((uninstall_failed + 1))
    fi
  done <"$order_file"

  rm -f "$resolved_file" "$tracked_file" "$selected_file" "$installed_selected_file" "$edges_file" "$order_file" "$unresolved_file"
  log_info "Uninstall summary: candidates=$uninstall_candidates tracked_matches=$uninstall_tracked_matches removed=$uninstall_removed skipped_not_installed=$uninstall_skipped_not_installed failed=$uninstall_failed unresolved_order=$uninstall_unresolved_order"
}

resolve_security_manifest_packages() {
  manifest_file="$1"
  output_file="$2"
  resolve_profile_concrete_packages "security" "$manifest_file" "$output_file"
}

state_tracked_security_packages_for_preset() {
  preset="$1"
  output_file="$2"
  state_tracked_packages_for_scope "security" "$preset" "$output_file"
}

compute_downgrade_delta() {
  from_packages_file="$1"
  to_packages_file="$2"
  tracked_from_file="$3"
  remove_file="$4"
  keep_file="$5"
  install_file="$6"

  tracked_from_resolved_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-tracked-resolved.XXXXXX")"
  if [ -s "$tracked_from_file" ]; then
    grep -Fxf "$tracked_from_file" "$from_packages_file" | awk 'NF > 0 && !seen[$0]++ { print $0 }' >"$tracked_from_resolved_file" || true
  else
    : >"$tracked_from_resolved_file"
  fi

  if [ -s "$to_packages_file" ] && [ -s "$tracked_from_resolved_file" ]; then
    grep -Fxf "$to_packages_file" "$tracked_from_resolved_file" | awk 'NF > 0 && !seen[$0]++ { print $0 }' >"$keep_file" || true
  else
    : >"$keep_file"
  fi

  if [ -s "$keep_file" ]; then
    grep -Fvx -f "$keep_file" "$tracked_from_resolved_file" >"$remove_file" || true
  else
    cat "$tracked_from_resolved_file" >"$remove_file"
  fi

  installed_now_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-installed-now.XXXXXX")"
  checked_to_count=0
  to_total_count="$(awk 'END { print NR + 0 }' "$to_packages_file")"
  : >"$installed_now_file"
  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    checked_to_count=$((checked_to_count + 1))
    if pacman -Q "$package_name" >/dev/null 2>&1; then
      printf '%s\n' "$package_name" >>"$installed_now_file"
    fi
    if [ $((checked_to_count % 50)) -eq 0 ]; then
      log_info "Downgrade target-check progress: $checked_to_count/$to_total_count checked"
    fi
  done <"$to_packages_file"

  if [ -s "$installed_now_file" ]; then
    grep -Fvx -f "$installed_now_file" "$to_packages_file" | awk 'NF > 0 && !seen[$0]++ { print $0 }' >"$install_file" || true
  else
    awk 'NF > 0 && !seen[$0]++ { print $0 }' "$to_packages_file" >"$install_file"
  fi

  rm -f "$tracked_from_resolved_file" "$installed_now_file"
}

uninstall_selected_packages_with_state() {
  profile="$1"
  preset="$2"
  source_manifest="$3"
  package_file="$4"
  summary_prefix="$5"

  selected_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-selected.XXXXXX")"
  edges_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-edges.XXXXXX")"
  order_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-order.XXXXXX")"
  unresolved_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-unresolved.XXXXXX")"

  removed=0
  skipped_not_installed=0
  failed=0
  unresolved_order=0

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    if pacman -Q "$package_name" >/dev/null 2>&1; then
      printf '%s\n' "$package_name" >>"$selected_file"
    else
      skipped_not_installed=$((skipped_not_installed + 1))
    fi
  done <"$package_file"

  selected_count="$(awk 'END { print NR + 0 }' "$selected_file")"
  if [ "$selected_count" -eq 0 ]; then
    log_info "$summary_prefix removal summary: removed=0 skipped_not_installed=$skipped_not_installed failed=0 unresolved_order=0"
    rm -f "$selected_file" "$edges_file" "$order_file" "$unresolved_file"
    return 0
  fi

  build_uninstall_dependency_edges "$selected_file" "$edges_file"
  plan_uninstall_order "$selected_file" "$edges_file" "$order_file" "$unresolved_file"
  if [ -s "$unresolved_file" ]; then
    unresolved_order="$(awk 'END { print NR + 0 }' "$unresolved_file")"
  fi

  order_display="$(tr '\n' ' ' <"$order_file" | sed -E 's/[[:space:]]+$//')"
  log_info "$summary_prefix removal order: $order_display"
  if [ "$unresolved_order" -gt 0 ]; then
    unresolved_display="$(tr '\n' ' ' <"$unresolved_file" | sed -E 's/[[:space:]]+$//')"
    log_warn "$summary_prefix removal unresolved ordering ($unresolved_order): $unresolved_display"
  fi

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue
    log_info "Removing downgrade package: $package_name"
    if [ "${DRY_RUN:-0}" = "1" ]; then
      print_command sudo pacman -Rns --noconfirm "$package_name"
      removed=$((removed + 1))
      continue
    fi

    if sudo pacman -Rns --noconfirm "$package_name"; then
      removed=$((removed + 1))
      state_mark_removed_package "$package_name" "$profile" "$preset" "$source_manifest"
    else
      log_warn "Failed to remove downgrade package: $package_name"
      failed=$((failed + 1))
    fi
  done <"$order_file"

  log_info "$summary_prefix removal summary: removed=$removed skipped_not_installed=$skipped_not_installed failed=$failed unresolved_order=$unresolved_order"
  rm -f "$selected_file" "$edges_file" "$order_file" "$unresolved_file"
}

install_selected_security_packages_for_preset() {
  target_preset="$1"
  target_manifest="$2"
  install_file="$3"
  summary_prefix="$4"

  install_candidates="$(awk 'END { print NR + 0 }' "$install_file")"
  if [ "$install_candidates" -eq 0 ]; then
    log_info "$summary_prefix install summary: installed=0 skipped_existing=0 failed=0"
    return 0
  fi

  installed=0
  skipped_existing=0
  failed=0
  SECURITY_SUDO_NOTICE_SHOWN=0

  while IFS= read -r package_name || [ -n "$package_name" ]; do
    [ -n "$package_name" ] || continue

    if pacman -Q "$package_name" >/dev/null 2>&1; then
      skipped_existing=$((skipped_existing + 1))
      continue
    fi

    if [ "${DRY_RUN:-0}" = "1" ]; then
      print_command sudo pacman -S --needed --noconfirm "$package_name"
      installed=$((installed + 1))
      continue
    fi

    install_log="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-install.XXXXXX")"
    if run_pacman_install_streaming "$install_log" "downgrade target install $package_name" "$package_name"; then
      installed=$((installed + 1))
      state_mark_installed_package "$package_name"
    else
      log_warn "Failed to install downgrade target package: $package_name"
      failed=$((failed + 1))
    fi
    rm -f "$install_log"
  done <"$install_file"

  log_info "$summary_prefix install summary: installed=$installed skipped_existing=$skipped_existing failed=$failed"
}

downgrade_security_preset() {
  from_preset="$1"
  to_preset="$2"
  manifest_from="$3"
  manifest_to="$4"
  apply_target="$5"

  from_packages_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-from.XXXXXX")"
  to_packages_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-to.XXXXXX")"
  tracked_from_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-tracked-from.XXXXXX")"
  remove_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-remove.XXXXXX")"
  keep_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-keep.XXXXXX")"
  install_file="$(mktemp "${TMPDIR:-/tmp}/omarchy-downgrade-install.XXXXXX")"

  resolve_security_manifest_packages "$manifest_from" "$from_packages_file"
  resolve_security_manifest_packages "$manifest_to" "$to_packages_file"
  state_tracked_security_packages_for_preset "$from_preset" "$tracked_from_file"
  compute_downgrade_delta "$from_packages_file" "$to_packages_file" "$tracked_from_file" "$remove_file" "$keep_file" "$install_file"

  from_count="$(awk 'END { print NR + 0 }' "$from_packages_file")"
  to_count="$(awk 'END { print NR + 0 }' "$to_packages_file")"
  tracked_from_count="$(awk 'END { print NR + 0 }' "$tracked_from_file")"
  keep_count="$(awk 'END { print NR + 0 }' "$keep_file")"
  remove_count="$(awk 'END { print NR + 0 }' "$remove_file")"
  install_count="$(awk 'END { print NR + 0 }' "$install_file")"

  log_info "Security downgrade summary (from=$from_preset to=$to_preset):"
  log_info "Downgrade sets: from_candidates=$from_count to_candidates=$to_count tracked_from=$tracked_from_count keep_shared=$keep_count remove_delta=$remove_count install_delta=$install_count apply_target=$apply_target"

  if [ "$remove_count" -eq 0 ]; then
    log_warn "No tracked source-only packages to remove for downgrade."
  else
    uninstall_selected_packages_with_state "security" "$from_preset" "$manifest_from" "$remove_file" "Downgrade"
  fi

  if [ "$apply_target" -eq 1 ]; then
    INSTALL_STATE_PROFILE="security"
    INSTALL_STATE_PRESET="$to_preset"
    INSTALL_STATE_MANIFEST="$manifest_to"
    export INSTALL_STATE_PROFILE INSTALL_STATE_PRESET INSTALL_STATE_MANIFEST
    install_selected_security_packages_for_preset "$to_preset" "$manifest_to" "$install_file" "Downgrade"
  else
    log_info "Downgrade target install skipped (apply_target=0)"
  fi

  rm -f "$from_packages_file" "$to_packages_file" "$tracked_from_file" "$remove_file" "$keep_file" "$install_file"
}

install_single_package() {
  package_name="$1"
  log_info "Installing package: $package_name"

  if pacman -Q "$package_name" >/dev/null 2>&1; then
    run_cmd yay -S --noconfirm --needed "$package_name"
    return 0
  fi

  run_cmd yay -S --noconfirm --needed "$package_name"
  if [ "${DRY_RUN:-0}" = "0" ] && pacman -Q "$package_name" >/dev/null 2>&1; then
    state_mark_installed_package "$package_name"
  fi
}

install_profile_applications() {
  profile="$1"
  manifest_file="$2"
  preset="${SECURITY_PRESET:--}"
  if [ "$profile" != "security" ]; then
    preset="-"
  fi

  INSTALL_STATE_PROFILE="$profile"
  INSTALL_STATE_PRESET="$preset"
  INSTALL_STATE_MANIFEST="$manifest_file"
  export INSTALL_STATE_PROFILE INSTALL_STATE_PRESET INSTALL_STATE_MANIFEST

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
    SECURITY_SUDO_NOTICE_SHOWN=0
    export SEC_GROUPS_RESOLVED SEC_GROUPS_MISSING SEC_PACKAGES_TOTAL SEC_PACKAGES_ALREADY_INSTALLED
    export SEC_PACKAGES_INSTALLED SEC_PACKAGES_FAILED SEC_RETRY_COUNT SECURITY_SUDO_NOTICE_SHOWN

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
