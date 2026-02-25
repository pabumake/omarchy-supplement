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
    targets="$(resolve_security_targets "$manifest_file" "$bundles_file")"
    if [ -z "$targets" ]; then
      log_warn "No security groups found in $manifest_file"
      return 0
    fi

    log_info "Resolved security install targets:"
    for target in $targets; do
      log_info "  - $target"
      install_security_group "$target"
    done
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
