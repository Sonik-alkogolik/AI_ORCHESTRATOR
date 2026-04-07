$ErrorActionPreference = "Stop"
. "$PSScriptRoot/common.ps1"

$cfg = Read-AgentConfig
$workTimeout = [int](Get-CfgValue -Config $cfg -Key "WORK_TIMEOUT" -DefaultValue "120")
$maxParallel = [int](Get-CfgValue -Config $cfg -Key "MAX_PARALLEL_TASKS" -DefaultValue "2")
$codexCmd = $cfg["CODEX_CMD"]
$codexTemp = Get-CfgValue -Config $cfg -Key "CODEX_TEMPERATURE" -DefaultValue "0.7"
$codexTokens = Get-CfgValue -Config $cfg -Key "CODEX_MAX_TOKENS" -DefaultValue "2000"

function Invoke-Codex {
  param([string]$TaskDir, [string]$Prompt)
  $codeDir = Join-Path $TaskDir "code"
  New-Item -ItemType Directory -Force -Path $codeDir | Out-Null
  $input = Join-Path $TaskDir "code/prompt_input.txt"
  $output = Join-Path $TaskDir "code/output.txt"
  Set-Content -LiteralPath $input -Value $Prompt -Encoding UTF8
  $args = @("--temperature", $codexTemp, "--max-tokens", $codexTokens, "--input", $input, "--output", $output)
  $exit = Invoke-ModelCli -CommandPath $codexCmd -Arguments $args
  return ($exit -eq 0)
}

function Process-Task {
  param([string]$TaskDir)
  if (-not (Acquire-TaskLock -TaskDir $TaskDir)) { return }
  try {
    $status = (Get-Content -LiteralPath (Join-Path $TaskDir "status.txt") | Select-Object -First 1).Trim()
    if ($status -notin @("pending", "bug")) { return }
    Set-TaskStatus -TaskDir $TaskDir -Status "working"
    $iter = Increment-TaskIteration -TaskDir $TaskDir
    Set-TaskStartTime -TaskDir $TaskDir
  } finally {
    Release-TaskLock -TaskDir $TaskDir
  }

  $prompt = Get-Content -LiteralPath (Join-Path $TaskDir "prompt.txt") -Raw
  if ($iter -gt 1 -and (Test-Path (Join-Path $TaskDir "review.txt"))) {
    $prompt += "`n`nFix the issues from the previous review:`n" + (Get-Content -LiteralPath (Join-Path $TaskDir "review.txt") -Raw)
  }
  if (Invoke-Codex -TaskDir $TaskDir -Prompt $prompt) {
    Set-TaskStatus -TaskDir $TaskDir -Status "review"
  } else {
    Set-TaskStatus -TaskDir $TaskDir -Status "error"
  }
  Clear-TaskStartTime -TaskDir $TaskDir
}

function Check-Timeouts {
  $taskRoot = Join-Path $Script:Workspace "tasks"
  foreach ($dir in Get-ChildItem -LiteralPath $taskRoot -Directory -ErrorAction SilentlyContinue) {
    $statusFile = Join-Path $dir.FullName "status.txt"
    if (-not (Test-Path $statusFile)) { continue }
    $status = (Get-Content -LiteralPath $statusFile | Select-Object -First 1).Trim()
    if ($status -eq "working" -and (Test-TaskTimeout -TaskDir $dir.FullName -TimeoutSeconds $workTimeout)) {
      Set-TaskStatus -TaskDir $dir.FullName -Status "timeout"
      Clear-TaskStartTime -TaskDir $dir.FullName
    }
  }
}

$targets = @()
$targets += Get-TasksByStatus -Status "bug"
$targets += Get-TasksByStatus -Status "pending"
$targets = $targets | Select-Object -First $maxParallel
foreach ($t in $targets) { Process-Task -TaskDir $t }
Check-Timeouts
