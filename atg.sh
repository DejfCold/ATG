#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

INFO='[INFO]'
WARN='[WARN]'
home_dir=${HOME:?HOME must be set}
app_dir="$home_dir/apps"
applications_dir="$home_dir/.local/share/applications"
icons_root="$home_dir/.local/share/icons/hicolor"

mkdir -p -- "$app_dir" "$applications_dir"

# Escape a pathname as one Desktop Entry Exec argument.
desktop_exec_arg() {
	local value=$1
	value=${value//\\/\\\\}
	value=${value//\"/\\\"}
	value=${value//%/%%}
	value=${value//\$/\\\$}
	value=${value//\`/\\\`}
	printf '"%s"' "$value"
}

declare -A present_apps=()
scan_mode=${1:-}
target_app=${2:-}
while IFS= read -r -d '' app; do
	[[ -f "$app" ]] || continue
	if [[ "$app" == *$'\n'* || "$app" == *$'\r'* ]]; then
		printf '%s AppImage paths cannot contain newline characters: %q\n' "$WARN" "$app" >&2
		continue
	fi
	app_id=$(printf '%s' "$app" | sha256sum | cut -c1-16)
	present_apps["$app_id"]=1
	if [[ "$scan_mode" == --cleanup || ( "$scan_mode" == --scan-one && "$app" != "$target_app" ) ]]; then
		continue
	fi
	printf '%s Processing %s\n' "$INFO" "$app"
	chmod u+x -- "$app"
	tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ATG.XXXXXXXX")
	if ! (cd "$tmp_dir" && "$app" --appimage-extract >/dev/null); then
		printf '%s Could not extract %s\n' "$WARN" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	root="$tmp_dir/squashfs-root"
	if [[ ! -d "$root" ]]; then
		printf '%s Extraction did not create squashfs-root for %s\n' "$WARN" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi

	mapfile -d '' desktop_files < <(find "$root" -maxdepth 1 -type f -name '*.desktop' -print0)
	if (( ${#desktop_files[@]} != 1 )); then
		printf '%s Expected one root-level desktop file in %s; found %d\n' "$WARN" "$app" "${#desktop_files[@]}" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	desktop_file=${desktop_files[0]}
	icon_name=$(awk '
		/^\[Desktop Entry\]$/ { main = 1; next }
		/^\[/ { main = 0 }
		main && /^Icon=/ { sub(/^Icon=/, ""); print; exit }
	' "$desktop_file")
	if [[ -z "$icon_name" || "$icon_name" == */* ]]; then
		printf '%s Missing or unsupported Icon entry in %s\n' "$WARN" "$desktop_file" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	icon_file=
	for ext in png jpg jpeg; do
		if [[ -f "$root/$icon_name.$ext" ]]; then icon_file="$root/$icon_name.$ext"; break; fi
	done
	if [[ -z "$icon_file" ]]; then
		printf '%s Could not find a PNG/JPG icon named %s in %s\n' "$WARN" "$icon_name" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	if ! command -v identify >/dev/null || ! icon_size=$(identify -format '%wx%h' -- "$icon_file" 2>/dev/null) || [[ ! "$icon_size" =~ ^[0-9]+x[0-9]+$ ]]; then
		printf '%s Could not read icon dimensions for %s (ImageMagick identify is required)\n' "$WARN" "$icon_file" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi

	launcher="$applications_dir/atg-$app_id.desktop"
	icon_target="$icons_root/$icon_size/apps/atg-$app_id.${icon_file##*.}"
	app_exec=$(desktop_exec_arg "$app")
	exec_line=$(awk '
		/^\[Desktop Entry\]$/ { main = 1; next }
		/^\[/ { main = 0 }
		main && /^Exec=/ { sub(/^Exec=/, ""); print; exit }
	' "$desktop_file")
	if [[ -z "$exec_line" ]]; then
		printf '%s No Exec entry in %s\n' "$WARN" "$desktop_file" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	exec_suffix=$(printf '%s\n' "$exec_line" | awk '
		{
			quoted = 0
			escaped = 0
			for (i = 1; i <= length($0); i++) {
				ch = substr($0, i, 1)
				if (escaped) { escaped = 0; continue }
				if (quoted && ch == "\\") { escaped = 1; continue }
				if (ch == "\"") { quoted = !quoted; continue }
				if (!quoted && ch ~ /[ \t]/) { print substr($0, i); exit }
			}
		}')
	desktop_tmp="$desktop_file.atg"
	if ! ATG_DESKTOP_EXEC="Exec=$app_exec$exec_suffix" ATG_DESKTOP_ICON="Icon=$icon_target" \
		awk '
			/^\[Desktop Entry\]$/ { main = 1; print; next }
			/^\[/ { main = 0 }
			main && /^TryExec=/ { next }
			main && /^Exec=/ { print ENVIRON["ATG_DESKTOP_EXEC"]; exec_count++; next }
			main && /^Icon=/ { print ENVIRON["ATG_DESKTOP_ICON"]; icon_count++; next }
			{ print }
			END { if (!exec_count || !icon_count) exit 1 }
		' "$desktop_file" > "$desktop_tmp" || ! mv -- "$desktop_tmp" "$desktop_file"; then
		printf '%s Could not update desktop file for %s\n' "$WARN" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	if ! mkdir -p -- "${icon_target%/*}" || ! cp -- "$desktop_file" "$launcher" || ! cp -- "$icon_file" "$icon_target"; then
		printf '%s Could not install launcher/icon for %s\n' "$WARN" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	rm -rf -- "$tmp_dir"
done < <(find "$app_dir" -maxdepth 1 -type f -iname '*.appimage' -print0)

# Remove stale ATG-owned launchers and only icons below our own icon directory.
for launcher in "$applications_dir"/atg-*.desktop; do
	[[ -f "$launcher" ]] || continue
	launcher_id=${launcher##*/atg-}
	launcher_id=${launcher_id%.desktop}
	[[ "$launcher_id" =~ ^[a-f0-9]{16}$ ]] || continue
	[[ ${present_apps[$launcher_id]+yes} ]] && continue
	icon_value=
	while IFS= read -r line; do
		case "$line" in
			Icon=*) icon_value=${line#Icon=} ;;
		esac
	done < "$launcher"
	rm -f -- "$launcher"
	if [[ "$icon_value" == "$icons_root"/* ]]; then rm -f -- "$icon_value"; fi
done

printf '%s Finished\n' "$INFO"
