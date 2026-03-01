#!/bin/sh

installer_manifest_entries() {
  manifest_file="$1"

  awk '
    function trim(s) {
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      return s
    }

    {
      line = $0
      sub(/[[:space:]]*#.*/, "", line)
      line = trim(line)
      if (line == "") {
        next
      }

      count = split(line, parts, /\|/)
      if (count != 3) {
        printf "[ERROR] Invalid installer manifest line (expected Name|ProbeCommand|InstallerURL): %s\n", $0 > "/dev/stderr"
        exit 1
      }

      name = trim(parts[1])
      probe = trim(parts[2])
      url = trim(parts[3])

      if (name == "" || probe == "" || url == "") {
        printf "[ERROR] Invalid installer manifest line (empty field): %s\n", $0 > "/dev/stderr"
        exit 1
      }

      printf "%s|%s|%s\n", name, probe, url
    }
  ' "$manifest_file"
}

install_manifest_custom_tools() {
  manifest_file="$1"

  require_readable_file "$manifest_file"
  require_cmd bash
  require_cmd curl

  entries="$(installer_manifest_entries "$manifest_file")"
  if [ -z "$entries" ]; then
    log_info "No custom installers found in $manifest_file"
    return 0
  fi

  while IFS='|' read -r tool_name probe_cmd installer_url; do
    [ -n "$tool_name" ] || continue

    if command -v "$probe_cmd" >/dev/null 2>&1; then
      log_info "Skipping custom installer '$tool_name' (probe command found: $probe_cmd)"
      continue
    fi

    log_info "Running custom installer '$tool_name' from $installer_url"
    run_cmd sh -c 'curl -fsSL "$1" | bash' sh "$installer_url"

    if [ "${DRY_RUN:-0}" = "0" ] && ! command -v "$probe_cmd" >/dev/null 2>&1; then
      log_warn "Installer completed but probe command was not found in PATH: $probe_cmd"
    fi
  done <<EOF
$entries
EOF
}
