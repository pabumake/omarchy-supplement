#!/bin/sh

require_profile_configuration_scripts() {
  profile="$1"
  config_dir="$2"
  found=0

  base_script="$config_dir/configure.$profile.sh"
  if [ -e "$base_script" ]; then
    require_readable_file "$base_script"
    found=1
  fi

  for script_path in "$config_dir"/configure."$profile".app.*.sh; do
    if [ ! -e "$script_path" ]; then
      continue
    fi
    require_readable_file "$script_path"
    found=1
  done

  if [ "$found" -eq 0 ]; then
    log_warn "No configuration scripts found for profile '$profile' in $config_dir"
  fi
}

run_configuration_script() {
  script_path="$1"
  require_readable_file "$script_path"
  log_info "Running configuration script: $script_path"

  if [ -x "$script_path" ]; then
    run_cmd "$script_path"
  else
    run_cmd sh "$script_path"
  fi
}

manifest_has_package() {
  manifest_file="$1"
  package_name="$2"
  awk -v target="$package_name" '
    {
      line=$0
      sub(/[[:space:]]*#.*/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      if (line == target) {
        found = 1
        exit
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$manifest_file"
}

run_profile_configuration() {
  profile="$1"
  config_dir="$2"
  manifest_file="$3"
  found=0

  base_script="$config_dir/configure.$profile.sh"
  if [ -e "$base_script" ]; then
    found=1
    run_configuration_script "$base_script"
  fi

  for script_path in "$config_dir"/configure."$profile".app.*.sh; do
    if [ ! -e "$script_path" ]; then
      continue
    fi

    found=1
    script_name="$(basename -- "$script_path")"
    app_name="${script_name#configure.$profile.app.}"
    app_name="${app_name%.sh}"

    if manifest_has_package "$manifest_file" "$app_name"; then
      run_configuration_script "$script_path"
    else
      log_info "Skipping configuration script $script_path (app '$app_name' not in $manifest_file)"
    fi
  done

  if [ "$found" -eq 0 ]; then
    log_warn "Configuration phase skipped: no scripts found for profile '$profile'"
  fi
}
