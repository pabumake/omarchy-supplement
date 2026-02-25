# Omarchy Supplement

Profile-driven setup for Omarchy/Arch machines.

## Repository Layout

- `application/`: profile manifests only (`application.<profile>.txt`)
- `cfg/`: static config assets used by configuration scripts
- `configuration/`: post-install tweaks (`configure.<profile>.sh`, helper config scripts, and `configure.<profile>.app.<app>.sh`)
- `helper/`: shared setup/runtime helpers

## Profiles

- `general`: baseline for all machines
- `work`: work-only delta profile (does not include `general`)
- `security`: placeholder profile (no apps/tweaks defined yet)

## Entrypoints

Only these root scripts are public:

- `./setup-general.sh`
- `./setup-work.sh`
- `./setup-security.sh`

Supported flags:

- `--dry-run`
- `--apps-only`
- `--skip-config`
- `--help`

## Recommended Work Machine Flow

1. `./setup-general.sh`
2. `./setup-work.sh`

## Configuration Naming Convention

- Base profile script:
  - `configuration/configure.<profile>.sh`
- App-specific profile script:
  - `configuration/configure.<profile>.app.<app>.sh`

Execution behavior:

1. Run base script first (if present)
2. Run app scripts in lexical order
3. Run an app script only when `<app>` exists as an exact token in `application/application.<profile>.txt`
4. Unknown app scripts are skipped with a log message

Example:

- Manifest entry: `zen-browser-bin`
- Matching script: `configuration/configure.general.app.zen-browser-bin.sh`

## Adding Apps and Tweaks

1. Add package name to `application/application.<profile>.txt`
2. Optional: add `configuration/configure.<profile>.app.<package>.sh` for app-specific post-install tweaks

## Security Placeholder

`setup-security.sh` currently runs against placeholder files and exits successfully with clear messaging. Populate `application/application.security.txt` and add security config scripts when ready.

## Breaking Changes

- Root legacy wrappers were removed:
  - `install-*.sh`
  - `master-installation.sh`
  - `uninstall-pup.sh`
  - `install-dotfiles.sh`
  - `install-omarchy-overrides.sh`
- `arc/` was removed from the repository.
