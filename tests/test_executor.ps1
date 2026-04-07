$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$file = Join-Path $root "agents/executor.sh"
if (-not (Test-Path $file)) { throw "Missing $file" }
$content = Get-Content -Raw -LiteralPath $file

$mustHave = @(
  'execute_with_codex\(\)',
  'process_task\(\)',
  'check_timeouts_loop\(\)',
  'process_tasks_loop\(\)',
  'update_status\s+"\$task_dir"\s+"working"',
  'update_status\s+"\$task_dir"\s+"review"'
)

foreach ($rx in $mustHave) {
  if ($content -notmatch $rx) {
    throw "executor.sh missing required pattern: $rx"
  }
}

Write-Host "executor test passed"
