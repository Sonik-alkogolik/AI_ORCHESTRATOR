$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$file = Join-Path $root "agents/reviewer.ps1"
if (-not (Test-Path $file)) { throw "Missing $file" }
$content = Get-Content -Raw -LiteralPath $file

$mustHave = @(
  'function Invoke-QwenReview',
  'function Process-ReviewTask',
  'function Check-ReviewTimeouts',
  'Set-TaskStatus\s+-TaskDir\s+\$TaskDir\s+-Status\s+"reviewing"',
  'Set-TaskStatus\s+-TaskDir\s+\$TaskDir\s+-Status\s+"bug"',
  'Set-TaskStatus\s+-TaskDir\s+\$TaskDir\s+-Status\s+"done"'
)

foreach ($rx in $mustHave) {
  if ($content -notmatch $rx) {
    throw "reviewer.ps1 missing required pattern: $rx"
  }
}

Write-Host "reviewer test passed"
