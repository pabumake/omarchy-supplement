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
  --uninstall   Uninstall tracked packages for the selected profile
  --import-current-state  Import currently installed manifest packages into uninstall tracking (requires --uninstall)
  --downgrade-from  Security preset source for downgrade: basic|standard|full
  --downgrade-to    Security preset target for downgrade: basic|standard|full
  --apply-target    When downgrading, install missing target preset packages after removal
  --state-file  Override install-state ledger path (default: ~/.local/state/omarchy-supplement/install-state.tsv)
  --preset      Security preset: basic|standard|full (security profile only)
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
  UNINSTALL=0
  IMPORT_CURRENT_STATE=0
  DOWNGRADE_FROM=""
  DOWNGRADE_TO=""
  APPLY_TARGET=0
  SECURITY_PRESET=""
  STATE_FILE="${STATE_FILE:-}"

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
      --uninstall)
        UNINSTALL=1
        ;;
      --import-current-state)
        IMPORT_CURRENT_STATE=1
        ;;
      --downgrade-from)
        shift
        if [ "$#" -eq 0 ]; then
          log_error "Missing value for --downgrade-from"
          setup_usage "$(basename -- "$entrypoint_path")"
          return 1
        fi
        DOWNGRADE_FROM="$1"
        ;;
      --downgrade-from=*)
        DOWNGRADE_FROM="${1#--downgrade-from=}"
        ;;
      --downgrade-to)
        shift
        if [ "$#" -eq 0 ]; then
          log_error "Missing value for --downgrade-to"
          setup_usage "$(basename -- "$entrypoint_path")"
          return 1
        fi
        DOWNGRADE_TO="$1"
        ;;
      --downgrade-to=*)
        DOWNGRADE_TO="${1#--downgrade-to=}"
        ;;
      --apply-target)
        APPLY_TARGET=1
        ;;
      --state-file)
        shift
        if [ "$#" -eq 0 ]; then
          log_error "Missing value for --state-file"
          setup_usage "$(basename -- "$entrypoint_path")"
          return 1
        fi
        STATE_FILE="$1"
        ;;
      --state-file=*)
        STATE_FILE="${1#--state-file=}"
        ;;
      --preset)
        shift
        if [ "$#" -eq 0 ]; then
          log_error "Missing value for --preset"
          setup_usage "$(basename -- "$entrypoint_path")"
          return 1
        fi
        SECURITY_PRESET="$1"
        ;;
      --preset=*)
        SECURITY_PRESET="${1#--preset=}"
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
  downgrade_requested=0
  if [ -n "$DOWNGRADE_FROM" ] || [ -n "$DOWNGRADE_TO" ] || [ "$APPLY_TARGET" -eq 1 ]; then
    downgrade_requested=1
  fi
  if [ "$IMPORT_CURRENT_STATE" -eq 1 ] && [ "$UNINSTALL" -ne 1 ]; then
    log_error "--import-current-state requires --uninstall"
    return 1
  fi
  if [ "$downgrade_requested" -eq 1 ] && { [ "$UNINSTALL" -eq 1 ] || [ "$IMPORT_CURRENT_STATE" -eq 1 ]; }; then
    log_error "Downgrade mode cannot be combined with --uninstall or --import-current-state"
    return 1
  fi

  if [ "$PROFILE" = "security" ]; then
    if [ -z "$SECURITY_PRESET" ]; then
      SECURITY_PRESET="standard"
    fi

    case "$SECURITY_PRESET" in
      basic|standard|full)
        ;;
      *)
        log_error "Invalid security preset: $SECURITY_PRESET"
        log_error "Supported values: basic, standard, full"
        return 1
        ;;
    esac

    MANIFEST_FILE="$PROJECT_ROOT/application/application.security.$SECURITY_PRESET.txt"

    if [ "$downgrade_requested" -eq 1 ]; then
      if [ -z "$DOWNGRADE_FROM" ] || [ -z "$DOWNGRADE_TO" ]; then
        log_error "Downgrade requires both --downgrade-from and --downgrade-to"
        return 1
      fi

      case "$DOWNGRADE_FROM" in
        basic|standard|full)
          ;;
        *)
          log_error "Invalid --downgrade-from preset: $DOWNGRADE_FROM"
          log_error "Supported values: basic, standard, full"
          return 1
          ;;
      esac
      case "$DOWNGRADE_TO" in
        basic|standard|full)
          ;;
        *)
          log_error "Invalid --downgrade-to preset: $DOWNGRADE_TO"
          log_error "Supported values: basic, standard, full"
          return 1
          ;;
      esac
      if [ "$DOWNGRADE_FROM" = "$DOWNGRADE_TO" ]; then
        log_error "Downgrade source and target presets must differ"
        return 1
      fi
    fi
  else
    if [ -n "$SECURITY_PRESET" ]; then
      log_error "--preset is only supported for the security profile"
      return 1
    fi
    if [ "$downgrade_requested" -eq 1 ]; then
      log_error "Downgrade flags are only supported for the security profile"
      return 1
    fi
    MANIFEST_FILE="$PROJECT_ROOT/application/application.$PROFILE.txt"
  fi
  CONFIG_DIR="$PROJECT_ROOT/configuration"

  export DRY_RUN PROJECT_ROOT PROFILE SECURITY_PRESET STATE_FILE DOWNGRADE_FROM DOWNGRADE_TO APPLY_TARGET

  log_info "Starting setup for profile '$PROFILE'"
  if [ "$DRY_RUN" -eq 1 ]; then
    log_info "Dry-run mode enabled"
  fi
  if [ "$PROFILE" = "security" ]; then
    log_info "Security preset selected: $SECURITY_PRESET"
  fi
  if [ "$downgrade_requested" -eq 1 ]; then
    log_info "Security downgrade requested: from=$DOWNGRADE_FROM to=$DOWNGRADE_TO apply_target=$APPLY_TARGET"
  fi

  preflight_arch_omarchy
  if [ "$PROFILE" = "security" ]; then
    preflight_security_requirements
    security_prebootstrap_blackarch "$PROJECT_ROOT"
  fi

  require_readable_file "$MANIFEST_FILE"

  if [ "$downgrade_requested" -eq 1 ]; then
    manifest_from="$PROJECT_ROOT/application/application.security.$DOWNGRADE_FROM.txt"
    manifest_to="$PROJECT_ROOT/application/application.security.$DOWNGRADE_TO.txt"
    require_readable_file "$manifest_from"
    require_readable_file "$manifest_to"

    downgrade_security_preset "$DOWNGRADE_FROM" "$DOWNGRADE_TO" "$manifest_from" "$manifest_to" "$APPLY_TARGET"
    log_info "Setup completed successfully"
    return 0
  fi

  if [ "$UNINSTALL" -eq 1 ]; then
    if [ "$PROFILE" = "security" ]; then
      selected_preset="$SECURITY_PRESET"
    else
      selected_preset="-"
    fi

    if [ "$IMPORT_CURRENT_STATE" -eq 1 ]; then
      import_profile_install_state "$PROFILE" "$MANIFEST_FILE" "$selected_preset"
    else
      uninstall_profile_applications "$PROFILE" "$MANIFEST_FILE" "$selected_preset"
    fi

    log_info "Setup completed successfully"
    return 0
  fi

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
