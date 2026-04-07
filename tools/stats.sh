#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$ROOT/workspace/tasks"

count() {
  local status="$1"
  local n=0
  shopt -s nullglob
  for d in "$WS"/task_*/; do
    [[ -f "$d/status.txt" ]] || continue
    [[ "$(cat "$d/status.txt")" == "$status" ]] && n=$((n + 1))
  done
  shopt -u nullglob
  echo "$n"
}

echo "pending=$(count pending)"
echo "working=$(count working)"
echo "review=$(count review)"
echo "reviewing=$(count reviewing)"
echo "bug=$(count bug)"
echo "done=$(count done)"
echo "failed=$(count failed)"
echo "timeout=$(count timeout)"
echo "error=$(count error)"
