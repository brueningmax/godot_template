#!/usr/bin/env bash
# Exports release builds with the presets in export_presets.cfg and zips them.
#
#   tools/export.sh                      # all presets: Windows Desktop, Linux, Web
#   tools/export.sh Linux "Web"          # only these
#   GODOT=/path/to/godot tools/export.sh
#
# Output: build/<platform>/ and build/<name>-<platform>.zip, where <name> comes
# from config/name in project.godot. Needs the export templates for your Godot
# version (Editor > Manage Export Templates, or see docs/TEMPLATE_GUIDE.md).
#
# Godot exits with 0 even when an export has errors, so the logs are scanned.

set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
OUT="${EXPORT_DIR:-build}"

fail() {
	printf '\nFAILED: %s\n' "$1" >&2
	exit 1
}

scan_log() {
	if sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -E '^(ERROR|SCRIPT ERROR)'; then
		fail "$2 logged errors (full log: $1)"
	fi
}

command -v "$GODOT" >/dev/null 2>&1 || fail "Godot not found: set GODOT=/path/to/godot"

name=$(sed -n 's/^config\/name="\(.*\)"$/\1/p' project.godot)
slug=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
[ -n "$slug" ] || slug=game

if [ "$#" -gt 0 ]; then presets=("$@"); else presets=("Windows Desktop" "Linux" "Web"); fi
mkdir -p "$OUT"

# A fresh clone has no .godot/ import cache yet; exports need it.
"$GODOT" --headless --path . --import --quit >"$OUT/import.log" 2>&1
scan_log "$OUT/import.log" "Import"

for preset in "${presets[@]}"; do
	case "$preset" in
	"Windows Desktop") dir=windows file="$slug.exe" ;;
	"Linux") dir=linux file="$slug.x86_64" ;;
	"Web") dir=web file="index.html" ;;
	*) fail "Unknown preset '$preset' (known: Windows Desktop, Linux, Web)" ;;
	esac

	printf '==> %s -> %s/%s/%s\n' "$preset" "$OUT" "$dir" "$file"
	rm -rf "${OUT:?}/$dir" "$OUT/$slug-$dir.zip"
	mkdir -p "$OUT/$dir"
	log="$OUT/export-$dir.log"
	"$GODOT" --headless --path . --export-release "$preset" "$OUT/$dir/$file" >"$log" 2>&1
	code=$?
	[ "$code" -eq 0 ] || { tail -n 30 "$log"; fail "Export '$preset' exited with code $code (log: $log)"; }
	scan_log "$log" "Export '$preset'"
	[ -s "$OUT/$dir/$file" ] || fail "Export '$preset' produced no $file (log: $log)"

	if command -v zip >/dev/null 2>&1; then
		(cd "$OUT/$dir" && zip -qr "../$slug-$dir.zip" .)
		printf '    %s/%s-%s.zip\n' "$OUT" "$slug" "$dir"
	else
		printf '    (zip not installed; skipped packaging)\n'
	fi
done

printf '\nExports finished in %s/\n' "$OUT"
