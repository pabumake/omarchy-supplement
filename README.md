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
- `--uninstall`
- `--import-current-state` (requires `--uninstall`)
- `--state-file <path>`
- `--preset <basic|standard|full>` (security profile only)
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

Security preset examples:

- `./setup-security.sh` (defaults to `standard`)
- `./setup-security.sh --preset basic`
- `./setup-security.sh --preset full`

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
6. During `--dry-run`, configuration scripts are still executed with `DRY_RUN=1` for full visibility.

Example:

- Manifest entry: `zen-browser-bin`
- Matching script: `configuration/configure.general.app.zen-browser-bin.sh`

## Adding Apps and Tweaks

1. Add package name to `application/application.<profile>.txt`
2. Optional: add `configuration/configure.<profile>.app.<package>.sh` for app-specific post-install tweaks

## Custom Installer Manifests

For tools that are not installed from package manifests, use profile installer manifests with this format:

- `Name|ProbeCommand|InstallerURL`

Current custom installer manifest:

- `application/application.general.installers.txt`

Execution behavior (`configuration/configure.general.installers.sh`):

1. Skip entry when `ProbeCommand` already exists in `PATH`
2. Otherwise run installer via:
   - `curl -fsSL <InstallerURL> | bash`
3. In `--dry-run`, print the installer command without executing it

Current `general` entry:

- `gh-manager` via `https://raw.githubusercontent.com/pabumake/gh-manager/main/scripts/install.sh`

Related package dependency for this workflow:

- `github-cli` is installed from `application/application.general.txt`

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

## Default Wallpaper (General)

`general` includes wallpaper setup via:

- `configuration/configure.general.wallpaper.sh`

Behavior:

- Downloads default wallpaper (if missing) from:
  - `https://raw.githubusercontent.com/pabumake/catpucchin-latte-wallpapers/main/wallpaper/catpucchin-dark-omarchy-label.jpg`
- Stores it at:
  - `~/.config/omarchy/backgrounds/custom/catpucchin-dark-omarchy-label.jpg`
- Updates Omarchy background symlink:
  - `~/.config/omarchy/current/background`

Notes:

- This is a one-time default apply and does not force wallpaper on every login.
- Download failure is non-fatal by default (warn and continue).
- `hyprland-overrides.conf` is not used for wallpaper downloading in this mode.

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
- In `general` configuration discovery, pup uninstall is executed first.
- The script prints a final summary with removal/skip counters.

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
2. Security installs from preset manifests:
   - `application/application.security.basic.txt`
   - `application/application.security.standard.txt` (default)
   - `application/application.security.full.txt`
3. Security configuration scripts

Security manifest token types:

- `bundle-*`: alias resolved from `cfg/blackarch-bundles.conf`
- `blackarch-*`: direct BlackArch group

Security installs use:

- default mode: resolve `blackarch-*` groups to concrete package members, then install packages in non-interactive batches
- package installs use:
  - `sudo pacman -S --needed --noconfirm <package...>`
- `SECURITY_INSTALL_MODE=legacy-groups` keeps direct group installs (may become interactive)

Security preset intent:

- `basic`: lean baseline (`bundle-security-basic`)
- `standard`: recommended baseline (`bundle-security-standard`)
- `full`: full pentester stack (`bundle-security-full`)

Notes:

- `security` is delta-only; run `setup-general.sh` first.
- BlackArch `strap.sh` is checksum-verified against the checksum parsed from `https://blackarch.org/downloads.html`.
- Package-level install failures are retried with provider defaults when possible (for example `tessdata -> tesseract-data-eng`), then skipped with a warning summary.
- Security package installation streams pacman output live; after the first sudo password prompt, output continues in real time.
- Compatibility alias: `bundle-kali-core` maps to the same targets as `bundle-security-full`.

Troubleshooting:

- If some security packages cannot be installed due to stale/broken repo dependencies, setup continues and prints:
  - `Security install summary: ... failed=<n> retries=<n>`
  - `Security packages skipped after retries: <package list>`
- Blank output after the sudo prompt should no longer occur during chunk installs.

## Intelligent Uninstall

All setup entrypoints support uninstall mode:

- `./setup-general.sh --uninstall`
- `./setup-work.sh --uninstall`
- `./setup-security.sh --uninstall --preset full`

Uninstall behavior:

- Removes only packages tracked as installed/imported by this tool for the selected profile/preset.
- Uses dependency-aware remove ordering.
- Continues on package-level removal failures and prints a summary.
- Keeps pup-specific debloat (`configure.general.pup-uninstall.sh`) separate.

State ledger:

- Default path: `~/.local/state/omarchy-supplement/install-state.tsv`
- Override with: `--state-file <path>`
- Format:
  - `package<TAB>profile<TAB>preset<TAB>timestamp<TAB>source_manifest<TAB>status`
  - `status` values: `installed`, `imported`, `removed`

Bootstrap import for existing systems (installed before tracking existed):

- `./setup-security.sh --uninstall --import-current-state --preset full`
- `./setup-general.sh --uninstall --import-current-state`

Dry-run examples:

- `./setup-security.sh --uninstall --preset full --dry-run`
- `./setup-general.sh --uninstall --dry-run`

## Security Downgrade

Downgrade mode is available for security presets only:

- `./setup-security.sh --downgrade-from full --downgrade-to basic --dry-run`
- `./setup-security.sh --downgrade-from full --downgrade-to standard`
- Optional target install step:
  - `./setup-security.sh --downgrade-from full --downgrade-to basic --apply-target`

Downgrade semantics:

- Keeps packages shared by source/target presets.
- Removes only source-only packages that are tracked in state for the source preset.
- By default, does not install target preset packages (`remove-only delta`).
- `--apply-target` installs missing target packages and records them as `installed` under the target preset.

Prerequisite for systems installed before tracking:

- `./setup-security.sh --uninstall --import-current-state --preset full`

## Breaking Changes

- Root legacy wrappers were removed:
  - `install-*.sh`
  - `master-installation.sh`
  - `uninstall-pup.sh`
  - `install-dotfiles.sh`
  - `install-omarchy-overrides.sh`
- `arc/` was removed from the repository.
