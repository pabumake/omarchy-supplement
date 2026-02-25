#!/bin/sh

. "$PROJECT_ROOT/helper/common.sh"
. "$PROJECT_ROOT/helper/applications.sh"
. "$PROJECT_ROOT/helper/configure.sh"
. "$PROJECT_ROOT/helper/security.sh"

detect_profile_from_entrypoint() {
  entrypoint_path="$1"
  entrypoint_name="$(basename -- "$entrypoint_path")"

  case "$entrypoint_name" in
    setup-*.sh)
      profile="${entrypoint_name#setup-}"
      profile="${profile%.sh}"
      ;;
    *)
      log_error "Cannot infer profile from entrypoint: $entrypoint_name"
      return 1
      ;;
  esac

  case "$profile" in
    general|work|security)
      printf '%s\n' "$profile"
      ;;
    *)
      log_error "Unsupported profile inferred from entrypoint: $profile"
      return 1
      ;;
  esac
}

setup_usage() {
  script_name="$1"
  cat <<EOF
Usage: ./$script_name [options]

Options:
  --dry-run     Print commands without executing them
  --apps-only   Install applications only
  --skip-config Skip configuration phase
  --help        Show this help
EOF
}

run_setup_from_entrypoint() {
  entrypoint_path="$1"
  shift

  PROFILE="$(detect_profile_from_entrypoint "$entrypoint_path")"
  DRY_RUN=0
  SKIP_CONFIG=0
  APPS_ONLY=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --skip-config)
        SKIP_CONFIG=1
        ;;
      --apps-only)
        APPS_ONLY=1
        ;;
      --help|-h)
        setup_usage "$(basename -- "$entrypoint_path")"
        return 0
        ;;
      *)
        log_error "Unknown argument: $1"
        setup_usage "$(basename -- "$entrypoint_path")"
        return 1
        ;;
    esac
    shift
  done

  if [ "$APPS_ONLY" -eq 1 ]; then
    SKIP_CONFIG=1
  fi

  MANIFEST_FILE="$PROJECT_ROOT/application/application.$PROFILE.txt"
  CONFIG_DIR="$PROJECT_ROOT/configuration"

  export DRY_RUN PROJECT_ROOT PROFILE

  log_info "Starting setup for profile '$PROFILE'"
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "Dry-run mode enabled"
  fi

  preflight_arch_omarchy
  if [ "$PROFILE" = "security" ]; then
    preflight_security_requirements
    security_prebootstrap_blackarch "$PROJECT_ROOT"
  fi

  require_readable_file "$MANIFEST_FILE"
  if [ "$SKIP_CONFIG" -eq 0 ]; then
    require_profile_configuration_scripts "$PROFILE" "$CONFIG_DIR"
  fi

  install_profile_applications "$PROFILE" "$MANIFEST_FILE"

  if [ "$SKIP_CONFIG" -eq 0 ]; then
    run_profile_configuration "$PROFILE" "$CONFIG_DIR" "$MANIFEST_FILE"
  else
    log_info "Skipping configuration phase"
  fi

  log_info "Setup completed successfully"
}
