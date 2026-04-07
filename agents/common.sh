#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE="$PROJECT_ROOT/workspace"
CONFIG_FILE="$PROJECT_ROOT/config/agents.conf"

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  else
    echo -e "${RED}Config not found: $CONFIG_FILE${NC}" >&2
    exit 1
  fi
}

ensure_workspace() {
  mkdir -p "$WORKSPACE/tasks" "$WORKSPACE/completed" "$WORKSPACE/logs"
}

log() {
  local agent="$1"
  local level="$2"
  local msg="$3"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ "$LOG_LEVEL" == "DEBUG" || "$level" != "DEBUG" ]]; then
    echo "[$ts] [$agent] [$level] $msg" >> "$WORKSPACE/logs/${agent}.log"
    if [[ "$level" == "ERROR" ]]; then
      echo -e "${RED}[$agent] $msg${NC}" >&2
    fi
  fi
}

get_tasks_by_status() {
  local status="$1"
  local task_dir current_status
  shopt -s nullglob
  for task_dir in "$WORKSPACE/tasks"/task_*/; do
    [[ -d "$task_dir" && -f "$task_dir/status.txt" ]] || continue
    current_status="$(cat "$task_dir/status.txt" 2>/dev/null || true)"
    [[ "$current_status" == "$status" ]] && printf '%s\n' "$task_dir"
  done
  shopt -u nullglob
}

update_status() {
  local task_dir="$1"
  local new_status="$2"
  local task_id
  task_id="$(basename "$task_dir")"
  echo "$new_status" > "$task_dir/status.txt"
  log "system" "INFO" "Task $task_id -> $new_status"
}

get_iteration() {
  local task_dir="$1"
  cat "$task_dir/iteration" 2>/dev/null || echo "0"
}

increment_iteration() {
  local task_dir="$1"
  local iter
  iter="$(get_iteration "$task_dir")"
  iter=$((iter + 1))
  echo "$iter" > "$task_dir/iteration"
  echo "$iter"
}

set_start_time() {
  local task_dir="$1"
  date +%s > "$task_dir/start_time"
}

clear_start_time() {
  local task_dir="$1"
  rm -f "$task_dir/start_time"
}

check_timeout() {
  local task_dir="$1"
  local timeout_seconds="$2"
  local start_file="$task_dir/start_time"
  [[ -f "$start_file" ]] || return 1

  local start_time now elapsed
  start_time="$(cat "$start_file")"
  now="$(date +%s)"
  elapsed=$((now - start_time))
  [[ "$elapsed" -gt "$timeout_seconds" ]]
}

acquire_task_lock() {
  local task_dir="$1"
  mkdir "$task_dir/.lock" 2>/dev/null
}

release_task_lock() {
  local task_dir="$1"
  rmdir "$task_dir/.lock" 2>/dev/null || true
}

load_config
ensure_workspace
