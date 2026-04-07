#!/usr/bin/env bash

source "$(dirname "$0")/agents/common.sh"

ORCHESTRATOR_NAME="orchestrator"
RUNNING=true

cleanup() {
  log "$ORCHESTRATOR_NAME" "INFO" "Stopping orchestrator"
  RUNNING=false
  exit 0
}
trap cleanup SIGTERM SIGINT

check_dependencies() {
  local missing=0
  command -v "$CODEX_CMD" >/dev/null 2>&1 || { echo "Missing: $CODEX_CMD"; missing=1; }
  command -v "$QWEN_CMD" >/dev/null 2>&1 || { echo "Missing: $QWEN_CMD"; missing=1; }
  if [[ "$missing" -eq 1 ]]; then
    echo "Install required CLIs and retry."
    exit 1
  fi
}

create_task() {
  local prompt="$1"
  local task_id task_dir
  task_id="task_$(date +%s)_$RANDOM"
  task_dir="$WORKSPACE/tasks/$task_id"
  mkdir -p "$task_dir/code"
  printf '%s\n' "$prompt" > "$task_dir/prompt.txt"
  echo "pending" > "$task_dir/status.txt"
  echo "0" > "$task_dir/iteration"
  log "$ORCHESTRATOR_NAME" "INFO" "Created task $task_id"
  echo "$task_id"
}

show_stats() {
  local p w r rv b d f t e
  p="$(get_tasks_by_status "pending" | wc -l | tr -d ' ')"
  w="$(get_tasks_by_status "working" | wc -l | tr -d ' ')"
  r="$(get_tasks_by_status "review" | wc -l | tr -d ' ')"
  rv="$(get_tasks_by_status "reviewing" | wc -l | tr -d ' ')"
  b="$(get_tasks_by_status "bug" | wc -l | tr -d ' ')"
  d="$(get_tasks_by_status "done" | wc -l | tr -d ' ')"
  f="$(get_tasks_by_status "failed" | wc -l | tr -d ' ')"
  t="$(get_tasks_by_status "timeout" | wc -l | tr -d ' ')"
  e="$(get_tasks_by_status "error" | wc -l | tr -d ' ')"
  echo "pending=$p working=$w review=$r reviewing=$rv bug=$b done=$d failed=$f timeout=$t error=$e"
}

show_tasks() {
  local task_dir status iteration task_id
  shopt -s nullglob
  for task_dir in "$WORKSPACE/tasks"/task_*/; do
    task_id="$(basename "$task_dir")"
    status="$(cat "$task_dir/status.txt" 2>/dev/null || echo unknown)"
    iteration="$(cat "$task_dir/iteration" 2>/dev/null || echo 0)"
    echo "$task_id [$status] iteration=$iteration"
  done
  shopt -u nullglob
}

show_logs() {
  local agent="${1:-}"
  local lines="${2:-20}"
  if [[ -n "$agent" ]]; then
    [[ -f "$WORKSPACE/logs/${agent}.log" ]] && tail -n "$lines" "$WORKSPACE/logs/${agent}.log"
    return
  fi
  shopt -s nullglob
  local file
  for file in "$WORKSPACE/logs/"*.log; do
    echo "=== $(basename "$file") ==="
    tail -n "$lines" "$file"
  done
  shopt -u nullglob
}

start_agents() {
  if command -v tmux >/dev/null 2>&1; then
    tmux has-session -t ai_exec 2>/dev/null || tmux new-session -d -s ai_exec "./agents/executor.sh"
    tmux has-session -t ai_rev 2>/dev/null || tmux new-session -d -s ai_rev "./agents/reviewer.sh"
    return 0
  fi
  ./agents/executor.sh &
  ./agents/reviewer.sh &
}

interactive_menu() {
  while $RUNNING; do
    clear
    echo "AI ORCHESTRATOR"
    echo "--------------"
    show_stats
    echo
    show_tasks
    echo
    echo "[n] new task  [l] logs  [e] executor logs  [r] reviewer logs  [q] quit"
    read -r -t "$MONITOR_REFRESH" cmd || true
    case "${cmd:-}" in
      n|N)
        echo "Enter task prompt:"
        read -r prompt
        [[ -n "$prompt" ]] && create_task "$prompt" >/dev/null
        ;;
      l|L) show_logs "" 50; read -r -p "Enter to continue... " _ ;;
      e|E) show_logs "executor" 50; read -r -p "Enter to continue... " _ ;;
      r|R) show_logs "reviewer" 50; read -r -p "Enter to continue... " _ ;;
      q|Q) RUNNING=false; break ;;
    esac
  done
}

main() {
  case "${1:-}" in
    create)
      shift
      create_task "$*"
      exit 0
      ;;
    stats)
      show_stats
      exit 0
      ;;
  esac

  check_dependencies
  start_agents
  interactive_menu
}

main "$@"
