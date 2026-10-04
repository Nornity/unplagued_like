#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
GODOT_BIN="${GODOT_BIN:-godot}"
mkdir -p release
"$GODOT_BIN" --headless --path . --editor --quit
"$GODOT_BIN" --headless --path . --export-release "Windows Desktop" release/TheLastBell.exe
printf '\nBuilt: %s/release/TheLastBell.exe\n' "$PWD"
