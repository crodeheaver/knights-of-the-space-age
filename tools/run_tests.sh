#!/usr/bin/env bash
# Runs the headless unit/integration test suite. Fails if any test fails OR if
# any SCRIPT ERROR was printed (GDScript runtime errors abort a test silently).
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
OUT=$(mktemp)
timeout 600 $GODOT --headless --path . res://tests/test_runner.tscn -- "$@" > "$OUT" 2>&1
CODE=$?
grep -v "ALSA\|audio_driver\|All audio drivers\|at: init_output_device\|at: initialize (servers\|^\s*$" "$OUT"
if grep -q "SCRIPT ERROR" "$OUT"; then
  echo "TEST RUN FAILED: script errors were reported (see above)."
  CODE=1
fi
rm -f "$OUT"
exit $CODE
