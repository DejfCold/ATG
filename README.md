# ATG — AppImage To Gnome

ATG watches `~/apps` and creates per-user GNOME application launchers for AppImages placed there. It runs as a user systemd service and does not require root access.

ATG requires no additional packages to be installed on a typical Linux desktop distribution. It uses Bash, systemd user services, and standard core utilities such as `sha256sum`, which are already provided by the system. Each AppImage must contain one root-level `.desktop` file with `Type=Application`, `Name`, and `Exec` entries, plus a matching PNG, JPG, JPEG, or SVG icon.

Launchers and icons are installed under `$XDG_DATA_HOME` when it is set to an absolute path; otherwise ATG uses `~/.local/share`.

The user service and path units are installed under `$XDG_CONFIG_HOME/systemd/user` when it is set to an absolute path; otherwise ATG uses `~/.config/systemd/user`.

**Only add AppImages you trust.** ATG invokes each image with `--appimage-extract`; that operation runs the AppImage runtime as your user.

## Install

Download `atg-installer` from the latest GitHub release and run `bash atg-installer`. It is a self-contained Bash script with ATG's runtime, service unit, and path unit embedded; it installs everything for the current user, enables the watcher for future logins, and scans `~/apps` once during installation. No repository checkout or root access is needed. ATG then scans AppImages directly inside `~/apps` whenever the directory changes.

ATG stores each successfully processed AppImage's SHA-256 fingerprint and file signature in its generated launcher. Unchanged files with an intact launcher and icon are skipped without hashing or extraction. New or changed files are allowed to settle before ATG hashes and extracts them; no separate cache file is used.

ATG preserves simple `env NAME=value …` launch prefixes. It omits desktop action shortcuts because their commands may target helpers inside the AppImage, and skips launchers with unsupported wrapper commands instead of rewriting them incorrectly.

To install from a source checkout, run `bash install.sh`. CI builds an installer artifact on every branch push. Pushing a tag named `v*` (for example, `v1.0.0`) builds the same artifact and publishes a GitHub release with it attached. The artifact is generated from `atg.sh`, `atg.service`, `atg.path`, and `installer-runtime.sh` by `python3 build-installer.py`.

## Uninstall

```sh
systemctl --user disable --now atg.path
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
case "$config_home" in /*) ;; *) config_home="$HOME/.config" ;; esac
rm -f "$config_home/systemd/user/atg.path" "$config_home/systemd/user/atg.service" ~/.local/bin/atg.sh
systemctl --user daemon-reload
```

ATG-generated launchers and their icons use the `atg-` filename prefix. Remove those files from `$XDG_DATA_HOME/applications` and `$XDG_DATA_HOME/icons/hicolor` if `XDG_DATA_HOME` is set, or from `~/.local/share/applications` and `~/.local/share/icons/hicolor` otherwise, to remove launchers created before uninstalling.

## Nonstandard home directories

The service and path unit use systemd's `%h` home-directory specifier, so homes outside `/home/<username>` work without manual path edits.
