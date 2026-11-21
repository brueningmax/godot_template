#!/usr/bin/env bash
# Runs every check CI runs, in the same order. Stops at the first failure.
#
#   tools/check.sh                    # uses `godot` from PATH
#   GODOT=/path/to/godot tools/check.sh
#
# Needs: bash (Linux, macOS, or Git Bash on Windows), Godot 4.7, and the
# Python tools from requirements-dev.txt (pip install -r requirements-dev.txt).
#
# Why the log scanning: Godot exits with 0 even when scenes or resources fail
# to load; the problems only show up as "ERROR:" lines in its output.

set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
LOG_DIR="${CHECK_LOG_DIR:-.godot/check-logs}"  # .godot/ is git-ignored
mkdir -p "$LOG_DIR"

step() { printf '\n==> %s\n' "$1"; }

fail() {
	printf '\nFAILED: %s\n' "$1"
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		printf '### ❌ %s\n\nSee the step log for details.\n' "$1" >>"$GITHUB_STEP_SUMMARY"
	fi
	exit 1
}

# Run with a time limit where `timeout` exists (not on stock macOS).
limit() {
	local seconds="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then timeout "$seconds" "$@"; else "$@"; fi
}

# Fails if a Godot log contains engine or script errors (colour codes stripped).
scan_log() {
	local log="$1" what="$2"
	if sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E '^(ERROR|SCRIPT ERROR)'; then
		fail "$what logged errors (full log: $log)"
	fi
}

# Runs Godot with its output in $LOG_DIR/<name>.log (path left in $LOG) and
# fails on a non-zero exit code.
godot_run() {
	local name="$1" seconds="$2"
	shift 2
	LOG="$LOG_DIR/$name.log"
	limit "$seconds" "$GODOT" --headless --path . "$@" >"$LOG" 2>&1
	local code=$?
	if [ "$code" -ne 0 ]; then
		tail -n 40 "$LOG"
		fail "$name exited with code $code (full log: $LOG)"
	fi
}

command -v "$GODOT" >/dev/null 2>&1 || fail "Godot not found: set GODOT=/path/to/godot"
step "Godot $("$GODOT" --version 2>/dev/null | tail -n 1)"

step "Tool versions in sync (requirements-dev.txt vs .pre-commit-config.yaml)"
req=$(sed -n 's/^gdtoolkit==\(.*\)$/\1/p' requirements-dev.txt)
hook=$(grep -A1 'godot-gdscript-toolkit' .pre-commit-config.yaml | sed -n 's/^ *rev: *\(.*\)$/\1/p')
[ -n "$req" ] && [ "$req" = "$hook" ] ||
	fail "gdtoolkit version differs: requirements-dev.txt '$req', .pre-commit-config.yaml '$hook'"
echo "gdtoolkit $req"

step "Format (gdformat --check)"
gdformat --check . || fail "Formatting: run 'gdformat .'"

step "Lint (gdlint)"
gdlint . || fail "Lint problems"

step "Import project"
godot_run import 300 --import --quit
scan_log "$LOG" "Import"
echo "ok"

step "Compile all scripts (tools/check_scripts.gd)"
godot_run check_scripts 120 --script res://tools/check_scripts.gd
grep 'check_scripts:' "$LOG"

step "Smoke run: full game (boot, splash, main menu)"
godot_run smoke_main 60 --fixed-fps 60 --quit-after 400
scan_log "$LOG" "Smoke run of the main scene"
echo "ok"

step "Smoke run: hello_world.tscn on its own"
godot_run smoke_hello_world 60 --fixed-fps 60 --quit-after 120 res://scenes/game/hello_world/hello_world.tscn
scan_log "$LOG" "Smoke run of hello_world.tscn"
echo "ok"

step "Smoke run: quit while a sound plays (tools/quit_check.gd)"
godot_run quit_check 60 --script res://tools/quit_check.gd
scan_log "$LOG" "Quitting through GameState.quit()"
echo "ok"

step "Tests (GUT)"
junit="$PWD/$LOG_DIR/junit.xml"
limit 600 "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gjunit_xml_file="$junit" \
	| tee "$LOG_DIR/tests.log"
code=${PIPESTATUS[0]}
[ "$code" -eq 0 ] || fail "Tests failed (exit code $code)"

printf '\nAll checks passed.\n'
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	totals=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG_DIR/tests.log" | grep -E '^(Tests|Passing Tests|Asserts) ' | tr -s ' ')
	printf '### ✅ All checks passed\n\n```\n%s\n```\n' "$totals" >>"$GITHUB_STEP_SUMMARY"
fi
