# ATG — AppImage To Gnome

ATG watches `~/apps` and creates per-user GNOME application launchers for AppImages placed there. It runs as a user systemd service and does not require root access.

ATG requires Bash, systemd user services, `sha256sum`, and ImageMagick's `identify` command. Each AppImage must contain one root-level `.desktop` file and a matching PNG, JPG, or JPEG icon.

**Only add AppImages you trust.** ATG invokes each image with `--appimage-extract`; that operation runs the AppImage runtime as your user.

## Install

Install ImageMagick using your distribution's package manager. Then download `atg-installer` from the latest GitHub release and run `bash atg-installer`. It is a self-contained Bash script with ATG's runtime, service unit, and path unit embedded; it installs everything for the current user, enables the watcher for future logins, and scans `~/apps` once during installation. No repository checkout or root access is needed. ATG then scans AppImages directly inside `~/apps` whenever the directory changes.

To install from a source checkout, run `bash install.sh`. CI builds an installer artifact on every branch push. Pushing a tag named `v*` (for example, `v1.0.0`) builds the same artifact and publishes a GitHub release with it attached. The artifact is generated from `atg.sh`, `atg.service`, `atg.path`, and `installer-runtime.sh` by `python3 build-installer.py`.

## Uninstall

```sh
systemctl --user disable --now atg.path
rm -f ~/.config/systemd/user/atg.path ~/.config/systemd/user/atg.service ~/.local/bin/atg.sh
systemctl --user daemon-reload
```

ATG-generated launchers and their icons use the `atg-` filename prefix. Remove those files from `~/.local/share/applications` and `~/.local/share/icons/hicolor` if you want to remove the launchers created before uninstalling.

## Nonstandard home directories

The service and path unit use systemd's `%h` home-directory specifier, so homes outside `/home/<username>` work without manual path edits.
