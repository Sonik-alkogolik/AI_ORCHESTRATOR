#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/config/agents.conf"
CONFIG_BAK="$ROOT/config/agents.conf.bak"
WS="$ROOT/workspace"

cleanup() {
  if [[ -f "$CONFIG_BAK" ]]; then
    mv "$CONFIG_BAK" "$CONFIG"
  fi
  if [[ -n "${EXEC_PID:-}" ]]; then kill "$EXEC_PID" 2>/dev/null || true; fi
  if [[ -n "${REV_PID:-}" ]]; then kill "$REV_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT

cp "$CONFIG" "$CONFIG_BAK"
cat > "$CONFIG" << EOF
CODEX_CMD="$ROOT/tests/fixtures/mock_codex.sh"
QWEN_CMD="$ROOT/tests/fixtures/mock_qwen.sh"
MAX_ITERATIONS=3
REVIEW_TIMEOUT=30
WORK_TIMEOUT=120
MONITOR_REFRESH=2
MAX_PARALLEL_TASKS=2
CODEX_TEMPERATURE=0.0
QWEN_TEMPERATURE=0.0
CODEX_MAX_TOKENS=256
QWEN_MAX_TOKENS=256
LOG_LEVEL="DEBUG"
EOF

chmod +x "$ROOT"/agents/*.sh "$ROOT"/tests/*.sh "$ROOT"/tests/fixtures/*.sh "$ROOT"/tools/*.sh "$ROOT"/orchestrator.sh "$ROOT"/start_all.sh
"$ROOT/tools/cleanup.sh" >/dev/null

TASK_ID="$("$ROOT/orchestrator.sh" create "Write sort_unique implementation")"
[[ -n "$TASK_ID" ]]

"$ROOT/agents/executor.sh" &
EXEC_PID=$!
"$ROOT/agents/reviewer.sh" &
REV_PID=$!

deadline=$((SECONDS + 25))
while (( SECONDS < deadline )); do
  if [[ -d "$WS/completed/$TASK_ID" ]]; then
    status="$(cat "$WS/completed/$TASK_ID/status.txt")"
    [[ "$status" == "done" ]] || { echo "Expected done, got $status"; exit 1; }
    iter="$(cat "$WS/completed/$TASK_ID/iteration")"
    [[ "$iter" -ge 2 ]] || { echo "Expected >=2 iterations, got $iter"; exit 1; }
    echo "system test passed: $TASK_ID in $iter iterations"
    exit 0
  fi
  sleep 1
done

echo "Task did not complete in time"
exit 1
