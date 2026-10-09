#!/usr/bin/env bash
set -Eeuo pipefail

source_dir=${ATG_SOURCE_DIR:?ATG_SOURCE_DIR is not set}
bin_dir="$HOME/.local/bin"
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
[[ "$config_home" == /* ]] || config_home="$HOME/.config"
systemd_dir="$config_home/systemd/user"

for file in atg.sh atg.service atg.path; do
	if [[ ! -f "$source_dir/$file" ]]; then
		printf 'Missing installer payload: %s\n' "$file" >&2
		exit 1
	fi
done

command -v systemctl >/dev/null || { printf 'systemctl is required.\n' >&2; exit 1; }
command -v sha256sum >/dev/null || { printf 'sha256sum is required.\n' >&2; exit 1; }

mkdir -p -- "$HOME/apps" "$bin_dir" "$systemd_dir"
systemctl --user disable --now atg.path >/dev/null 2>&1 || true
systemctl --user stop atg.service >/dev/null 2>&1 || true
install -m 0755 -- "$source_dir/atg.sh" "$bin_dir/atg.sh"
install -m 0644 -- "$source_dir/atg.service" "$systemd_dir/atg.service"
install -m 0644 -- "$source_dir/atg.path" "$systemd_dir/atg.path"

systemctl --user daemon-reload
systemctl --user enable --now atg.path
systemctl --user start atg.service
printf 'ATG installed for %s. Add AppImages to %s/apps.\n' "${USER:-your user}" "$HOME"
