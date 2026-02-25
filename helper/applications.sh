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

  packages="$(manifest_packages "$manifest_file")"
  if [ -z "$packages" ]; then
    log_warn "No packages found in $manifest_file"
    return 0
  fi

  for package_name in $packages; do
    install_single_package "$package_name"
  done
}
