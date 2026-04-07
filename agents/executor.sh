#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

EXECUTOR_NAME="executor"
RUNNING=true
MAX_PARALLEL="${MAX_PARALLEL_TASKS:-3}"

cleanup() {
  log "$EXECUTOR_NAME" "INFO" "Stop signal received"
  RUNNING=false
  exit 0
}
trap cleanup SIGTERM SIGINT

execute_with_codex() {
  local task_dir="$1"
  local prompt="$2"
  local output_file="$task_dir/code/output.txt"
  local temp_prompt
  temp_prompt="$(mktemp)"
  printf '%s\n' "$prompt" > "$temp_prompt"

  local start end duration
  start="$(date +%s)"
  if $CODEX_CMD \
    --temperature "$CODEX_TEMPERATURE" \
    --max-tokens "$CODEX_MAX_TOKENS" \
    --input "$temp_prompt" \
    --output "$output_file" \
    2>> "$WORKSPACE/logs/codex_errors.log"; then
    end="$(date +%s)"
    duration=$((end - start))
    log "$EXECUTOR_NAME" "INFO" "Codex finished in ${duration}s"
    rm -f "$temp_prompt"
    return 0
  fi

  rm -f "$temp_prompt"
  return 1
}

process_task() {
  local task_dir="$1"
  local task_id status prompt iter bug_context
  task_id="$(basename "$task_dir")"

  acquire_task_lock "$task_dir" || return 0
  status="$(cat "$task_dir/status.txt" 2>/dev/null || true)"
  if [[ "$status" != "pending" && "$status" != "bug" ]]; then
    release_task_lock "$task_dir"
    return 0
  fi

  update_status "$task_dir" "working"
  iter="$(increment_iteration "$task_dir")"
  set_start_time "$task_dir"
  release_task_lock "$task_dir"

  prompt="$(cat "$task_dir/prompt.txt" 2>/dev/null || true)"
  if [[ -z "$prompt" ]]; then
    log "$EXECUTOR_NAME" "ERROR" "Prompt missing for $task_id"
    update_status "$task_dir" "error"
    clear_start_time "$task_dir"
    return 1
  fi

  if [[ "$iter" -gt 1 && -f "$task_dir/review.txt" ]]; then
    bug_context="$(cat "$task_dir/review.txt")"
    prompt="${prompt}

Fix the issues from the previous review:
${bug_context}
Return corrected final code."
  fi

  mkdir -p "$task_dir/code"
  if execute_with_codex "$task_dir" "$prompt"; then
    log "$EXECUTOR_NAME" "INFO" "Task $task_id complete on iteration $iter"
    update_status "$task_dir" "review"
    clear_start_time "$task_dir"
    return 0
  fi

  log "$EXECUTOR_NAME" "ERROR" "Task $task_id execution failed"
  update_status "$task_dir" "error"
  clear_start_time "$task_dir"
  return 1
}

check_timeouts_loop() {
  while $RUNNING; do
    local task_dir status
    shopt -s nullglob
    for task_dir in "$WORKSPACE/tasks"/task_*/; do
      [[ -d "$task_dir" ]] || continue
      status="$(cat "$task_dir/status.txt" 2>/dev/null || true)"
      if [[ "$status" == "working" ]] && check_timeout "$task_dir" "$WORK_TIMEOUT"; then
        log "$EXECUTOR_NAME" "ERROR" "Work timeout in $(basename "$task_dir")"
        update_status "$task_dir" "timeout"
        clear_start_time "$task_dir"
      fi
    done
    shopt -u nullglob
    sleep 5
  done
}

process_tasks_loop() {
  while $RUNNING; do
    local all_tasks=() task
    while IFS= read -r task; do all_tasks+=("$task"); done < <(get_tasks_by_status "bug")
    while IFS= read -r task; do all_tasks+=("$task"); done < <(get_tasks_by_status "pending")

    local running_count available_slots i
    running_count="$(jobs -r | wc -l | tr -d ' ')"
    available_slots=$((MAX_PARALLEL - running_count))

    if [[ "$available_slots" -gt 0 && "${#all_tasks[@]}" -gt 0 ]]; then
      for ((i=0; i<available_slots && i<${#all_tasks[@]}; i++)); do
        process_task "${all_tasks[$i]}" &
      done
    fi
    sleep 2
  done
}

main() {
  log "$EXECUTOR_NAME" "INFO" "Executor started"
  check_timeouts_loop &
  local timeout_pid=$!
  process_tasks_loop
  kill "$timeout_pid" 2>/dev/null || true
}

main
