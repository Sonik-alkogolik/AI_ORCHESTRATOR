$ErrorActionPreference = "Stop"
. "$PSScriptRoot/common.ps1"

$cfg = Read-AgentConfig
$reviewTimeout = [int](Get-CfgValue -Config $cfg -Key "REVIEW_TIMEOUT" -DefaultValue "30")
$maxIterations = [int](Get-CfgValue -Config $cfg -Key "MAX_ITERATIONS" -DefaultValue "3")
$qwenCmd = $cfg["QWEN_CMD"]
$qwenTemp = Get-CfgValue -Config $cfg -Key "QWEN_TEMPERATURE" -DefaultValue "0.3"
$qwenTokens = Get-CfgValue -Config $cfg -Key "QWEN_MAX_TOKENS" -DefaultValue "1000"

function Invoke-QwenReview {
  param([string]$TaskDir, [string]$Code)
  $promptFile = Join-Path $TaskDir "review_prompt.txt"
  $reviewFile = Join-Path $TaskDir "review.txt"
  $prompt = @"
You are a strict code reviewer. Analyze the code and find all important issues.

CODE:
```
$Code
```

Rules:
1) If code is good, answer exactly: OK
2) If code has issues, describe each issue in a short actionable format.
"@
  Set-Content -LiteralPath $promptFile -Value $prompt -Encoding UTF8
  $args = @("--temperature", $qwenTemp, "--max-tokens", $qwenTokens, "--input", $promptFile, "--output", $reviewFile)
  $exit = Invoke-ModelCli -CommandPath $qwenCmd -Arguments $args
  return ($exit -eq 0)
}

function Process-ReviewTask {
  param([string]$TaskDir)
  if (-not (Acquire-TaskLock -TaskDir $TaskDir)) { return }
  try {
    $status = (Get-Content -LiteralPath (Join-Path $TaskDir "status.txt") | Select-Object -First 1).Trim()
    if ($status -ne "review") { return }
    Set-TaskStatus -TaskDir $TaskDir -Status "reviewing"
    Set-TaskStartTime -TaskDir $TaskDir
  } finally {
    Release-TaskLock -TaskDir $TaskDir
  }

  $code = Get-Content -LiteralPath (Join-Path $TaskDir "code/output.txt") -Raw
  if (-not (Invoke-QwenReview -TaskDir $TaskDir -Code $code)) {
    Set-TaskStatus -TaskDir $TaskDir -Status "error"
    Clear-TaskStartTime -TaskDir $TaskDir
    return
  }

  $review = (Get-Content -LiteralPath (Join-Path $TaskDir "review.txt") -Raw).Trim()
  $iter = Get-TaskIteration -TaskDir $TaskDir
  if ($review -eq "OK") {
    $taskId = Split-Path -Leaf $TaskDir
    Set-TaskStatus -TaskDir $TaskDir -Status "done"
    $target = Join-Path $Script:Workspace "completed/$taskId"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item -Recurse -Force (Join-Path $TaskDir "*") $target
    Remove-Item -Recurse -Force -LiteralPath $TaskDir
    return
  }
  if ($iter -ge $maxIterations) { Set-TaskStatus -TaskDir $TaskDir -Status "failed" } else { Set-TaskStatus -TaskDir $TaskDir -Status "bug" }
  Clear-TaskStartTime -TaskDir $TaskDir
}

function Check-ReviewTimeouts {
  $taskRoot = Join-Path $Script:Workspace "tasks"
  foreach ($dir in Get-ChildItem -LiteralPath $taskRoot -Directory -ErrorAction SilentlyContinue) {
    $statusFile = Join-Path $dir.FullName "status.txt"
    if (-not (Test-Path $statusFile)) { continue }
    $status = (Get-Content -LiteralPath $statusFile | Select-Object -First 1).Trim()
    if ($status -eq "reviewing" -and (Test-TaskTimeout -TaskDir $dir.FullName -TimeoutSeconds $reviewTimeout)) {
      Set-TaskStatus -TaskDir $dir.FullName -Status "timeout"
      Clear-TaskStartTime -TaskDir $dir.FullName
    }
  }
}

$targets = Get-TasksByStatus -Status "review"
foreach ($t in $targets) { Process-ReviewTask -TaskDir $t }
Check-ReviewTimeouts
