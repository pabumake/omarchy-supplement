# Omarchy Supplement

Profile-driven setup for Omarchy/Arch machines.

## Repository Layout

- `application/`: profile package manifests and profile auxiliary manifests
- `cfg/`: static system config assets (for example Hyprland overrides, BlackArch bundle mappings)
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

Work profile package set includes:

- `microsoft-edge-stable-bin`
- `teams-for-linux-bin`
- `outlook-for-linux-bin`

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

## Webapp Manifests

Webapps are profile-driven from `application/application.<profile>.webapps.txt` files with this format:

- `Name|URL|IconURL`

Current webapp manifests:

- `application/application.general.webapps.txt`
- `application/application.work.webapps.txt`

`configuration/configure.work.webapps.sh` installs these wrappers via `omarchy-webapp-install`.

For compatibility, `Word` and `Excel` launchers are rewritten to force Microsoft Edge app-mode:

- `Exec=<edge-executable> --app=<url>`

If Edge cannot be resolved during a real run, work webapp configuration fails with an actionable message to install `microsoft-edge-stable-bin`.

## Pup Uninstall (General Debloat)

`general` includes an idempotent debloat step:

- `configuration/configure.general.pup-uninstall.sh`

This script removes unwanted Omarchy defaults using static manifests:

- `application/application.general.pup-remove.packages.txt`
- `application/application.general.pup-remove.webapps.txt`

Rules:

- Package removals only run when package is installed.
- Webapp removal only runs when desktop entry exists and `Exec=` contains:
  - `omarchy-launch-webapp`
  - `omarchy-webapp-handler`
- Non-wrapper desktop entries are skipped for safety.

Notes:

- AUR-installed packages can be removed with pacman because installed artifacts are pacman-managed.
- Keep pup manifests curated and explicit; runtime log parsing is intentionally not used.

Optional maintenance command to review manual removals:

```bash
rg "\[PACMAN\] Running 'pacman -R" /var/log/pacman.log
```

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
