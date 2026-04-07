$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$config = Join-Path $root "config/agents.conf"
$backup = Join-Path $root "config/agents.conf.bak.ps1test"
$workspace = Join-Path $root "workspace"

try {
  Copy-Item -LiteralPath $config -Destination $backup -Force

  $codex = Join-Path $root "tests/fixtures/mock_codex.cmd"
  $qwen = Join-Path $root "tests/fixtures/mock_qwen.cmd"
  @"
CODEX_CMD="$codex"
QWEN_CMD="$qwen"
MAX_ITERATIONS=3
REVIEW_TIMEOUT=30
WORK_TIMEOUT=120
MONITOR_REFRESH=1
MAX_PARALLEL_TASKS=2
CODEX_TEMPERATURE=0.0
QWEN_TEMPERATURE=0.0
CODEX_MAX_TOKENS=256
QWEN_MAX_TOKENS=256
LOG_LEVEL="DEBUG"
"@ | Set-Content -LiteralPath $config -Encoding UTF8

  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $workspace "tasks/*")
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $workspace "completed/*")
  Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $workspace "logs/*")

  $taskId = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "orchestrator.ps1") create "Write sort_unique implementation"
  if (-not $taskId) { throw "Task was not created" }

  $execScript = Join-Path $root "agents/executor_once.ps1"
  $reviewScript = Join-Path $root "agents/reviewer_once.ps1"

  $deadline = (Get-Date).AddSeconds(25)
  $completed = Join-Path $workspace "completed/$taskId"
  while ((Get-Date) -lt $deadline) {
    powershell -NoProfile -ExecutionPolicy Bypass -File $execScript | Out-Null
    powershell -NoProfile -ExecutionPolicy Bypass -File $reviewScript | Out-Null
    if (Test-Path $completed) {
      $status = (Get-Content -LiteralPath (Join-Path $completed "status.txt") | Select-Object -First 1).Trim()
      if ($status -ne "done") { throw "Expected done status, got $status" }
      $iter = [int](Get-Content -LiteralPath (Join-Path $completed "iteration") | Select-Object -First 1)
      if ($iter -lt 2) { throw "Expected at least 2 iterations, got $iter" }
      Write-Host "system test passed: $taskId in $iter iterations"
      exit 0
    }
    Start-Sleep -Seconds 1
  }
  throw "Task did not complete in time"
}
finally {
  if (Test-Path $backup) {
    Move-Item -LiteralPath $backup -Destination $config -Force
  }
}
