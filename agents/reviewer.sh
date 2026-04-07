#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

REVIEWER_NAME="reviewer"
RUNNING=true

cleanup() {
  log "$REVIEWER_NAME" "INFO" "Stop signal received"
  RUNNING=false
  exit 0
}
trap cleanup SIGTERM SIGINT

review_with_qwen() {
  local task_dir="$1"
  local code_output="$2"
  local review_file="$task_dir/review.txt"
  local prompt_file
  prompt_file="$(mktemp)"

  cat > "$prompt_file" << EOF
You are a strict code reviewer. Analyze the code and find all important issues.

CODE:
\`\`\`
$code_output
\`\`\`

Rules:
1) If code is good, answer exactly: OK
2) If code has issues, describe each issue in a short actionable format.
EOF

  if $QWEN_CMD \
    --temperature "$QWEN_TEMPERATURE" \
    --max-tokens "$QWEN_MAX_TOKENS" \
    --input "$prompt_file" \
    --output "$review_file" \
    2>> "$WORKSPACE/logs/qwen_errors.log"; then
    rm -f "$prompt_file"
    return 0
  fi

  rm -f "$prompt_file"
  return 1
}

process_task() {
  local task_dir="$1"
  local task_id status code_output review_text iter
  task_id="$(basename "$task_dir")"

  acquire_task_lock "$task_dir" || return 0
  status="$(cat "$task_dir/status.txt" 2>/dev/null || true)"
  if [[ "$status" != "review" ]]; then
    release_task_lock "$task_dir"
    return 0
  fi
  update_status "$task_dir" "reviewing"
  set_start_time "$task_dir"
  release_task_lock "$task_dir"

  if [[ ! -f "$task_dir/code/output.txt" ]]; then
    log "$REVIEWER_NAME" "ERROR" "Missing code output for $task_id"
    update_status "$task_dir" "error"
    clear_start_time "$task_dir"
    return 1
  fi

  code_output="$(cat "$task_dir/code/output.txt")"
  if ! review_with_qwen "$task_dir" "$code_output"; then
    log "$REVIEWER_NAME" "ERROR" "Qwen failed for $task_id"
    update_status "$task_dir" "error"
    clear_start_time "$task_dir"
    return 1
  fi

  review_text="$(tr -d '\r' < "$task_dir/review.txt" | sed 's/[[:space:]]*$//')"
  iter="$(get_iteration "$task_dir")"

  if [[ "$review_text" == "OK" ]]; then
    update_status "$task_dir" "done"
    mkdir -p "$WORKSPACE/completed/$task_id"
    cp -R "$task_dir"/. "$WORKSPACE/completed/$task_id"/ 2>/dev/null || true
    rm -rf "$task_dir"
    log "$REVIEWER_NAME" "INFO" "Task $task_id completed"
    return 0
  fi

  if [[ "$iter" -ge "$MAX_ITERATIONS" ]]; then
    update_status "$task_dir" "failed"
    log "$REVIEWER_NAME" "ERROR" "Task $task_id failed after $iter iterations"
  else
    update_status "$task_dir" "bug"
    log "$REVIEWER_NAME" "INFO" "Task $task_id marked as bug"
  fi
  clear_start_time "$task_dir"
}

check_timeouts_loop() {
  while $RUNNING; do
    local task_dir status
    shopt -s nullglob
    for task_dir in "$WORKSPACE/tasks"/task_*/; do
      [[ -d "$task_dir" ]] || continue
      status="$(cat "$task_dir/status.txt" 2>/dev/null || true)"
      if [[ "$status" == "reviewing" ]] && check_timeout "$task_dir" "$REVIEW_TIMEOUT"; then
        log "$REVIEWER_NAME" "ERROR" "Review timeout in $(basename "$task_dir")"
        update_status "$task_dir" "timeout"
        clear_start_time "$task_dir"
      fi
    done
    shopt -u nullglob
    sleep 5
  done
}

main_loop() {
  while $RUNNING; do
    local task
    while IFS= read -r task; do
      process_task "$task" &
    done < <(get_tasks_by_status "review")
    sleep 2
  done
}

main() {
  log "$REVIEWER_NAME" "INFO" "Reviewer started"
  check_timeouts_loop &
  local timeout_pid=$!
  main_loop
  kill "$timeout_pid" 2>/dev/null || true
}

main
