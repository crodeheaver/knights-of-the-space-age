#!/usr/bin/env bash
# Robustness sweep: re-runs the three bot playthroughs with different dice
# (AOTC_SEED_OFFSET) and prints one PASS/FAIL line per route per offset.
# Usage: tools/bot_sweep.sh [first_offset] [last_offset]
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
timeout 300 $GODOT --headless --path . --import > /dev/null 2>&1
A=${1:-1}; B=${2:-5}
pass=0; total=0
for o in $(seq "$A" "$B"); do
  OUT=$(AOTC_SEED_OFFSET=$o timeout 900 $GODOT --headless --path . res://tests/test_runner.tscn -- --only=playthrough 2>&1)
  while read -r line; do
    total=$((total+1))
    [[ "$line" == *PASS* ]] && pass=$((pass+1))
    echo "offset $o: $line"
  done < <(echo "$OUT" | grep -E "^\s+(PASS|FAIL) test_playthrough" | sed 's/^ *//')
  echo "$OUT" | grep "BOT: FAIL" | sort | uniq | sed "s/^/  offset $o /" | head -6
done
echo "SWEEP: $pass/$total route runs escaped"
