#!/usr/bin/env bash
# Re-imports the project headless and prints any script parse/compile errors.
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
timeout 300 $GODOT --headless --path . --import 2>&1 | grep -E -A1 "SCRIPT ERROR|Parse Error|Compile Error" | grep -v "^--$"
exit 0
