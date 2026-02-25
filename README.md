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
- `security`: BlackArch-on-Omarchy delta profile (run after `general`)

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

## Recommended Security Flow

1. `./setup-general.sh`
2. `./setup-security.sh`

## Configuration Naming Convention

- Base profile script:
  - `configuration/configure.<profile>.sh`
- App-specific profile script:
  - `configuration/configure.<profile>.app.<app>.sh`

Execution behavior:

1. Run base script first (if present)
2. Base profile scripts auto-discover and run `configure.<profile>.*.sh` scripts except:
   - `configure.<profile>.sh` itself
   - `configure.<profile>.app.*.sh` app-gated scripts
3. Run app scripts in lexical order
4. Run an app script only when `<app>` exists as an exact token in `application/application.<profile>.txt`
5. Unknown app scripts are skipped with a log message

Example:

- Manifest entry: `zen-browser-bin`
- Matching script: `configuration/configure.general.app.zen-browser-bin.sh`

## Adding Apps and Tweaks

1. Add package name to `application/application.<profile>.txt`
2. Optional: add `configuration/configure.<profile>.app.<package>.sh` for app-specific post-install tweaks

## Security Profile (BlackArch)

`setup-security.sh` performs:

1. Security pre-bootstrap to configure BlackArch repository (`configuration/configure.security.blackarch.sh`)
2. Security installs from `application/application.security.txt`
3. Security configuration scripts

Security manifest token types:

- `bundle-*`: alias resolved from `cfg/blackarch-bundles.conf`
- `blackarch-*`: direct BlackArch group

Security installs use:

- `sudo pacman -S --needed --noconfirm <blackarch-group>`

Notes:

- `security` is delta-only; run `setup-general.sh` first.
- BlackArch `strap.sh` is checksum-verified against the checksum parsed from `https://blackarch.org/downloads.html`.

## Breaking Changes

- Root legacy wrappers were removed:
  - `install-*.sh`
  - `master-installation.sh`
  - `uninstall-pup.sh`
  - `install-dotfiles.sh`
  - `install-omarchy-overrides.sh`
- `arc/` was removed from the repository.
