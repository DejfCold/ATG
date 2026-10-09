#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s nullglob

INFO='[INFO]'
WARN='[WARN]'
home_dir=${HOME:?HOME must be set}
app_dir="$home_dir/apps"
data_home=${XDG_DATA_HOME:-$home_dir/.local/share}
[[ "$data_home" == /* ]] || data_home="$home_dir/.local/share"
applications_dir="$data_home/applications"
icons_root="$data_home/icons/hicolor"
icons_root_real=$(realpath -m -- "$icons_root")

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

# Read dimensions from the PNG/JPEG headers using Bash and coreutils only.
icon_dimensions() {
	local file=$1 byte_count index marker length height width offset length_offset next_offset file_size
	local -a bytes=()
	if [[ ${file,,} == *.png ]]; then
		read -r -a bytes < <(od -An -tu1 -N24 -- "$file")
		if (( ${#bytes[@]} >= 24 )) && (( bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71 && bytes[4] == 13 && bytes[5] == 10 && bytes[6] == 26 && bytes[7] == 10 )); then
			height=$(( bytes[20] * 16777216 + bytes[21] * 65536 + bytes[22] * 256 + bytes[23] ))
			width=$(( bytes[16] * 16777216 + bytes[17] * 65536 + bytes[18] * 256 + bytes[19] ))
			(( width > 0 && height > 0 )) && printf '%sx%s' "$width" "$height"
		fi
		return
	fi

	read -r -a bytes < <(od -An -tu1 -N2 -- "$file")
	(( ${#bytes[@]} == 2 && bytes[0] == 255 && bytes[1] == 216 )) || return 1
	file_size=$(wc -c < "$file")
	offset=2
	while :; do
		read -r -a bytes < <(od -An -tu1 -j "$offset" -N16 -- "$file")
		byte_count=${#bytes[@]}
		(( byte_count >= 2 && bytes[0] == 255 )) || return 1
		index=1
		while (( index < byte_count && bytes[index] == 255 )); do ((index++)); done
		(( index < byte_count )) || return 1
		marker=${bytes[index]}
		length_offset=$(( offset + index + 1 ))
		case $marker in
			217|218) return 1 ;;
			216|1|208|209|210|211|212|213)
				next_offset=$length_offset
				(( next_offset > offset && next_offset < file_size )) || return 1
				offset=$next_offset
				continue
				;;
		esac
		read -r -a bytes < <(od -An -tu1 -j "$length_offset" -N2 -- "$file")
		(( ${#bytes[@]} == 2 )) || return 1
		length=$(( bytes[0] * 256 + bytes[1] ))
		(( length >= 2 )) || return 1
		case $marker in
			192|193|194|195|197|198|199|201|202|203|205|206|207)
				(( length >= 8 )) || return 1
				read -r -a bytes < <(od -An -tu1 -j "$((length_offset + 2))" -N5 -- "$file")
				(( ${#bytes[@]} == 5 )) || return 1
				height=$(( bytes[1] * 256 + bytes[2] ))
				width=$(( bytes[3] * 256 + bytes[4] ))
				(( width > 0 && height > 0 )) && printf '%sx%s' "$width" "$height"
				return
				;;
		esac
		next_offset=$(( length_offset + length ))
		(( next_offset > offset && next_offset < file_size )) || return 1
		offset=$next_offset
	done
}

desktop_main_value() {
	local file=$1 key=$2
	awk -v key="$key" '
		/^\[Desktop Entry\]$/ { main = 1; next }
		/^\[/ { if (main) exit; main = 0 }
		main {
			line = $0
			sub(/^[ \t]*/, "", line)
			if (index(line, key) != 1) next
			line = substr(line, length(key) + 1)
			sub(/^[ \t]*/, "", line)
			if (substr(line, 1, 1) != "=") next
			line = substr(line, 2)
			sub(/^[ \t]*/, "", line)
			sub(/[ \t]*$/, "", line)
			print line
			exit
		}
	' "$file"
}

wait_for_stable_appimage() {
	local file=$1 previous=$2 current stable=0
	while [[ -f "$file" ]]; do
		sleep 1
		current=$(stat -c '%s:%y:%z' -- "$file") || return 1
		if [[ "$current" == "$previous" ]]; then
			((stable += 1))
		else
			stable=0
			previous=$current
		fi
		if (( stable >= 3 )); then
			stable_appimage_stat=$current
			return 0
		fi
	done
	return 1
}

update_launcher_appimage_stat() {
	local launcher=$1 app_stat=$2 tmp_file="$1.atg-tmp"
	ATG_DESKTOP_APP_STAT="X-ATG-AppImage-Stat=$app_stat" awk '
		/^\[Desktop Entry\]$/ { main = 1; print; next }
		/^\[/ { if (main && !stat_count) print ENVIRON["ATG_DESKTOP_APP_STAT"]; main = 0 }
		main && /^[ \t]*X-ATG-AppImage-Stat[ \t]*=/ { print ENVIRON["ATG_DESKTOP_APP_STAT"]; stat_count++; next }
		{ print }
		END { if (main && !stat_count) print ENVIRON["ATG_DESKTOP_APP_STAT"] }
	' "$launcher" > "$tmp_file" && mv -f -- "$tmp_file" "$launcher" && seal_launcher "$launcher"
}

seal_launcher() {
	local launcher=$1 signature tmp_file="$1.atg-seal"
	signature=$(awk '!/^[ \t]*X-ATG-Launcher-SHA256[ \t]*=/' "$launcher" | sha256sum)
	signature=${signature%% *}
	ATG_DESKTOP_LAUNCHER_SIGNATURE="X-ATG-Launcher-SHA256=$signature" awk '
		/^\[Desktop Entry\]$/ { main = 1; print; next }
		/^\[/ { if (main && !signature_count) print ENVIRON["ATG_DESKTOP_LAUNCHER_SIGNATURE"]; main = 0 }
		main && /^[ \t]*X-ATG-Launcher-SHA256[ \t]*=/ { print ENVIRON["ATG_DESKTOP_LAUNCHER_SIGNATURE"]; signature_count++; next }
		{ print }
		END { if (main && !signature_count) print ENVIRON["ATG_DESKTOP_LAUNCHER_SIGNATURE"] }
	' "$launcher" > "$tmp_file" && mv -f -- "$tmp_file" "$launcher"
}

find_app_icon() {
	local root=$1 name=$2 candidate resolved root_real ext directory candidate_name
	local -a icon_dirs=("$root/usr/share/icons" "$root/usr/local/share/icons" "$root/share/icons" \
		"$root/usr/share/pixmaps" "$root/usr/local/share/pixmaps" "$root/share/pixmaps")
	local -a icon_names=()
	root_real=$(realpath -e -- "$root") || return 1
	if [[ "$name" == */* ]]; then
		if [[ "$name" == /* ]]; then candidate="$root$name"; else candidate="$root/$name"; fi
		resolve_app_icon "$root_real" "$candidate"
		return
	fi
	case ${name,,} in
		*.png|*.jpg|*.jpeg|*.svg) icon_names=("$name") ;;
		*) for ext in png jpg jpeg svg; do icon_names+=("$name.$ext"); done ;;
	esac
	for candidate_name in "${icon_names[@]}"; do
		if candidate=$(resolve_app_icon "$root_real" "$root/$candidate_name"); then printf '%s' "$candidate"; return 0; fi
	done
	for directory in "${icon_dirs[@]}"; do
		[[ -d "$directory" ]] || continue
		for candidate_name in "${icon_names[@]}"; do
			while IFS= read -r -d '' candidate; do
				if resolved=$(resolve_app_icon "$root_real" "$candidate"); then
					printf '%s' "$resolved"
					return 0
				fi
			done < <(find "$directory" \( -type f -o -type l \) -name "$candidate_name" -print0 2>/dev/null)
		done
	done
	return 1
}

resolve_app_icon() {
	local root_real=$1 candidate=$2 resolved
	resolved=$(realpath -e -- "$candidate") || return 1
	[[ "$resolved" == "$root_real"/* && -f "$resolved" ]] || return 1
	case ${resolved,,} in *.png|*.jpg|*.jpeg|*.svg) printf '%s' "$resolved" ;; *) return 1 ;; esac
}

# Remove only generated icon files whose resolved parent remains inside hicolor.
remove_managed_icon() {
	local path=$1 app_id=$2 basename parent resolved_parent
	[[ "$path" == "$icons_root"/* ]] || return 0
	basename=${path##*/}
	[[ "$basename" =~ ^atg-${app_id}\.(png|jpg|jpeg|svg)$ ]] || return 0
	parent=${path%/*}
	resolved_parent=$(realpath -e -- "$parent") || return 0
	[[ "$resolved_parent" == "$icons_root_real" || "$resolved_parent" == "$icons_root_real"/* ]] || return 0
	rm -f -- "$resolved_parent/$basename"
}

declare -A present_apps=()
declare -A scan_app_paths=()
declare -A scan_app_stats=()
scan_mode=${1:-}
target_app=${2:-}
scan_dir_stamp=$(stat -c '%Y:%y' -- "$app_dir")
scan_list=$(mktemp "${TMPDIR:-/tmp}/ATG-scan.XXXXXXXX")
tmp_dir=
cleanup() {
	[[ -z "$tmp_dir" ]] || rm -rf -- "$tmp_dir" 2>/dev/null || true
	[[ -z "$scan_list" ]] || rm -f -- "$scan_list" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if ! find "$app_dir" -maxdepth 1 -type f -iname '*.appimage' -print0 > "$scan_list"; then
	printf '%s Could not enumerate AppImages in %s; leaving existing launchers untouched\n' "$WARN" "$app_dir" >&2
	exit 1
fi
while IFS= read -r -d '' app; do
	[[ -f "$app" ]] || continue
	if [[ "$app" == *$'\n'* || "$app" == *$'\r'* ]]; then
		printf '%s AppImage paths cannot contain newline characters: %q\n' "$WARN" "$app" >&2
		continue
	fi
	app_id=$(printf '%s' "$app" | sha256sum | cut -c1-16)
	present_apps["$app_id"]=1
	launcher="$applications_dir/atg-$app_id.desktop"
	app_exec=$(desktop_exec_arg "$app")
	if [[ "$scan_mode" == --cleanup || ( "$scan_mode" == --scan-one && "$app" != "$target_app" ) ]]; then
		scan_app_paths["$app_id"]=$app
		scan_app_stats["$app_id"]=$(stat -c '%s:%y:%z' -- "$app")
		continue
	fi
	chmod u+x -- "$app"
	app_stat=$(stat -c '%s:%y:%z' -- "$app")
	scan_app_paths["$app_id"]=$app
	scan_app_stats["$app_id"]=$app_stat
	cached_launcher_valid=0
	if [[ -f "$launcher" ]]; then
		cached_icon=$(desktop_main_value "$launcher" Icon)
		cached_icon_fingerprint=$(desktop_main_value "$launcher" X-ATG-Icon-SHA256)
		cached_fingerprint=$(desktop_main_value "$launcher" X-ATG-AppImage-SHA256)
		cached_stat=$(desktop_main_value "$launcher" X-ATG-AppImage-Stat)
		cached_exec=$(desktop_main_value "$launcher" Exec)
		cached_metadata_fingerprint=$(desktop_main_value "$launcher" X-ATG-Desktop-SHA256)
		cached_launcher_signature=$(desktop_main_value "$launcher" X-ATG-Launcher-SHA256)
		cached_metadata_actual=$(printf 'Exec=%s\nIcon=%s' "$cached_exec" "$cached_icon" | sha256sum)
		cached_metadata_actual=${cached_metadata_actual%% *}
		cached_launcher_actual=$(awk '!/^[ \t]*X-ATG-Launcher-SHA256[ \t]*=/' "$launcher" | sha256sum)
		cached_launcher_actual=${cached_launcher_actual%% *}
		cached_icon_actual=
		if [[ "$cached_icon" == "$icons_root"/* && \
			"${cached_icon#"$icons_root"/}" =~ ^(scalable|[0-9]+x[0-9]+)/apps/atg-${app_id}\.(png|jpg|jpeg|svg)$ && \
			-f "$cached_icon" ]]; then
			cached_icon_actual=$(sha256sum < "$cached_icon")
			cached_icon_actual=${cached_icon_actual%% *}
		fi
		if [[ "$cached_fingerprint" =~ ^[a-f0-9]{64}$ && \
			"$cached_icon_fingerprint" == "$cached_icon_actual" && \
			"$cached_metadata_fingerprint" == "$cached_metadata_actual" && \
			"$cached_launcher_signature" == "$cached_launcher_actual" && \
			"$cached_icon" == "$icons_root"/* && \
			"${cached_icon#"$icons_root"/}" =~ ^(scalable|[0-9]+x[0-9]+)/apps/atg-${app_id}\.(png|jpg|jpeg|svg)$ && \
			-f "$cached_icon" && -n "$cached_exec" ]]; then
			cached_launcher_valid=1
			if [[ "$cached_stat" == "$app_stat" ]]; then continue; fi
		fi
	fi
	if ! wait_for_stable_appimage "$app" "$app_stat"; then
		printf '%s AppImage disappeared while waiting for a stable copy: %s\n' "$WARN" "$app" >&2
		continue
	fi
	app_stat=$stable_appimage_stat
	scan_app_stats["$app_id"]=$app_stat
	app_fingerprint=$(sha256sum < "$app")
	app_fingerprint=${app_fingerprint%% *}
	if (( cached_launcher_valid )) && [[ "$cached_fingerprint" == "$app_fingerprint" ]]; then
		if update_launcher_appimage_stat "$launcher" "$app_stat"; then continue; fi
	fi
	printf '%s Processing %s\n' "$INFO" "$app"
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
	desktop_name=$(desktop_main_value "$desktop_file" Name)
	desktop_type=$(desktop_main_value "$desktop_file" Type)
	if [[ -z "$desktop_name" || "$desktop_type" != Application ]]; then
		printf '%s Desktop file must define Name and Type=Application: %s\n' "$WARN" "$desktop_file" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	icon_name=$(desktop_main_value "$desktop_file" Icon)
	if [[ -z "$icon_name" ]]; then
		printf '%s Missing Icon entry in %s\n' "$WARN" "$desktop_file" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	if ! icon_file=$(find_app_icon "$root" "$icon_name"); then
		printf '%s Could not find a PNG/JPG/SVG icon for %s in %s\n' "$WARN" "$icon_name" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	if [[ ${icon_file,,} == *.svg ]]; then
		icon_size=scalable
	else
		if ! icon_size=$(icon_dimensions "$icon_file") || [[ ! "$icon_size" =~ ^[0-9]+x[0-9]+$ ]]; then
			printf '%s Could not read icon dimensions for %s\n' "$WARN" "$icon_file" >&2
			rm -rf -- "$tmp_dir"
			continue
		fi
	fi
	icon_ext=${icon_file##*.}
	icon_ext=${icon_ext,,}
	icon_target="$icons_root/$icon_size/apps/atg-$app_id.$icon_ext"
	icon_fingerprint=$(sha256sum < "$icon_file")
	icon_fingerprint=${icon_fingerprint%% *}
	previous_icon=
	if [[ -f "$launcher" ]]; then previous_icon=$(desktop_main_value "$launcher" Icon); fi
	exec_line=$(desktop_main_value "$desktop_file" Exec)
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
	desktop_metadata=$(printf 'Exec=%s\nIcon=%s' "$app_exec$exec_suffix" "$icon_target" | sha256sum)
	desktop_metadata=${desktop_metadata%% *}
	desktop_tmp="$desktop_file.atg"
	if ! ATG_APP_EXEC="$app_exec" ATG_DESKTOP_ICON="Icon=$icon_target" \
		ATG_DESKTOP_FINGERPRINT="X-ATG-AppImage-SHA256=$app_fingerprint" \
		ATG_DESKTOP_ICON_FINGERPRINT="X-ATG-Icon-SHA256=$icon_fingerprint" \
		ATG_DESKTOP_APP_STAT="X-ATG-AppImage-Stat=$app_stat" \
		ATG_DESKTOP_METADATA="X-ATG-Desktop-SHA256=$desktop_metadata" \
		awk '
			/^\[Desktop Entry\]$/ { main = 1; action = 0; print; next }
			/^\[Desktop Action / {
				if (main && !fingerprint_count) print ENVIRON["ATG_DESKTOP_FINGERPRINT"]
				if (main && !icon_fingerprint_count) print ENVIRON["ATG_DESKTOP_ICON_FINGERPRINT"]
				if (main && !app_stat_count) print ENVIRON["ATG_DESKTOP_APP_STAT"]
				if (main && !metadata_count) print ENVIRON["ATG_DESKTOP_METADATA"]
				main = 0; action = 1; print; next
			}
			/^\[/ {
				if (main && !fingerprint_count) print ENVIRON["ATG_DESKTOP_FINGERPRINT"]
				if (main && !icon_fingerprint_count) print ENVIRON["ATG_DESKTOP_ICON_FINGERPRINT"]
				if (main && !app_stat_count) print ENVIRON["ATG_DESKTOP_APP_STAT"]
				if (main && !metadata_count) print ENVIRON["ATG_DESKTOP_METADATA"]
				main = 0; action = 0
			}
			main && /^[ \t]*X-ATG-AppImage-SHA256[ \t]*=/ { print ENVIRON["ATG_DESKTOP_FINGERPRINT"]; fingerprint_count++; next }
			main && /^[ \t]*X-ATG-Icon-SHA256[ \t]*=/ { print ENVIRON["ATG_DESKTOP_ICON_FINGERPRINT"]; icon_fingerprint_count++; next }
			main && /^[ \t]*X-ATG-AppImage-Stat[ \t]*=/ { print ENVIRON["ATG_DESKTOP_APP_STAT"]; app_stat_count++; next }
			main && /^[ \t]*X-ATG-Desktop-SHA256[ \t]*=/ { print ENVIRON["ATG_DESKTOP_METADATA"]; metadata_count++; next }
			main && /^[ \t]*TryExec[ \t]*=/ { next }
			main && /^[ \t]*DBusActivatable[ \t]*=/ { next }
			(main || action) && /^[ \t]*Exec[ \t]*=/ {
				command = $0
				sub(/^[ \t]*Exec[ \t]*=[ \t]*/, "", command)
				suffix = ""
				quoted = 0
				escaped = 0
				for (i = 1; i <= length(command); i++) {
					ch = substr(command, i, 1)
					if (escaped) { escaped = 0; continue }
					if (quoted && ch == "\\") { escaped = 1; continue }
					if (ch == "\"") { quoted = !quoted; continue }
					if (!quoted && ch ~ /[ \t]/) { suffix = substr(command, i); break }
				}
				print "Exec=" ENVIRON["ATG_APP_EXEC"] suffix
				if (main) exec_count++
				next
			}
			main && /^[ \t]*Icon[ \t]*=/ { print ENVIRON["ATG_DESKTOP_ICON"]; icon_count++; next }
			{ print }
			END {
				if (main && !fingerprint_count) print ENVIRON["ATG_DESKTOP_FINGERPRINT"]
				if (main && !icon_fingerprint_count) print ENVIRON["ATG_DESKTOP_ICON_FINGERPRINT"]
				if (main && !app_stat_count) print ENVIRON["ATG_DESKTOP_APP_STAT"]
				if (main && !metadata_count) print ENVIRON["ATG_DESKTOP_METADATA"]
				if (!exec_count || !icon_count) exit 1
			}
		' "$desktop_file" > "$desktop_tmp" || ! mv -- "$desktop_tmp" "$desktop_file"; then
		printf '%s Could not update desktop file for %s\n' "$WARN" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	if ! seal_launcher "$desktop_file"; then
		printf '%s Could not seal launcher metadata for %s\n' "$WARN" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	if ! mkdir -p -- "${icon_target%/*}" || ! cp -- "$icon_file" "$icon_target" || ! cp -- "$desktop_file" "$launcher"; then
		printf '%s Could not install launcher/icon for %s\n' "$WARN" "$app" >&2
		rm -rf -- "$tmp_dir"
		continue
	fi
	if [[ "$previous_icon" == "$icons_root"/* && "$previous_icon" != "$icon_target" ]]; then
		remove_managed_icon "$previous_icon" "$app_id"
	fi
	rm -rf -- "$tmp_dir"
done < "$scan_list"

# Remove stale ATG-owned launchers and only icons below our own icon directory.
for launcher in "$applications_dir"/atg-*.desktop; do
	[[ -f "$launcher" ]] || continue
	launcher_id=${launcher##*/atg-}
	launcher_id=${launcher_id%.desktop}
	[[ "$launcher_id" =~ ^[a-f0-9]{16}$ ]] || continue
	[[ ${present_apps[$launcher_id]+yes} ]] && continue
	icon_value=
	icon_value=$(desktop_main_value "$launcher" Icon)
	rm -f -- "$launcher"
	remove_managed_icon "$icon_value" "$launcher_id"
done

# If files arrived or left during enumeration/processing, repeat after the
# directory has had a moment to settle. The launcher fingerprint makes this
# pass skip AppImages already handled above.
if [[ "$scan_mode" != --cleanup ]]; then
	sleep 1
	latest_scan_dir_stamp=$(stat -c '%Y:%y' -- "$app_dir")
	scan_changed=0
	[[ "$latest_scan_dir_stamp" == "$scan_dir_stamp" ]] || scan_changed=1
	for app_id in "${!scan_app_paths[@]}"; do
		app=${scan_app_paths[$app_id]}
		if [[ ! -f "$app" ]] || [[ $(stat -c '%s:%y:%z' -- "$app") != "${scan_app_stats[$app_id]}" ]]; then
			scan_changed=1
			break
		fi
	done
	if (( scan_changed )); then
		rm -f -- "$scan_list"
		trap - EXIT
		exec bash "$0" "$@"
	fi
fi

printf '%s Finished\n' "$INFO"
