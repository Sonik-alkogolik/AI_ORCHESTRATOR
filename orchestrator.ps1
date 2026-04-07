param(
  [string]$Command,
  [string[]]$PromptArgs
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/agents/common.ps1"

$cfg = Read-AgentConfig

function New-OrchestratorTask {
  param([Parameter(Mandatory = $true)][string]$Prompt)
  $id = "task_{0}_{1}" -f ([int][double]::Parse((Get-Date -UFormat %s))), (Get-Random -Maximum 99999)
  $dir = Join-Path $Script:Workspace "tasks/$id"
  New-Item -ItemType Directory -Force -Path (Join-Path $dir "code") | Out-Null
  Set-Content -LiteralPath (Join-Path $dir "prompt.txt") -Value $Prompt -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $dir "status.txt") -Value "pending" -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $dir "iteration") -Value "0" -Encoding UTF8
  return $id
}

function Get-OrchestratorStats {
  $statuses = @("pending","working","review","reviewing","bug","done","failed","timeout","error")
  $parts = foreach ($s in $statuses) {
    "{0}={1}" -f $s, ((Get-TasksByStatus -Status $s).Count)
  }
  $parts -join " "
}

function Start-OrchestratorAgents {
  $execPath = Join-Path $PSScriptRoot "agents/executor.ps1"
  $revPath = Join-Path $PSScriptRoot "agents/reviewer.ps1"
  Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$execPath) -WindowStyle Minimized | Out-Null
  Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$revPath) -WindowStyle Minimized | Out-Null
}

function Test-AgentCommands {
  $codexCmd = Get-CfgValue -Config $cfg -Key "CODEX_CMD" -DefaultValue "codex"
  $qwenCmd = Get-CfgValue -Config $cfg -Key "QWEN_CMD" -DefaultValue "qwen"
  $missing = @()
  if (-not (Get-Command $codexCmd -ErrorAction SilentlyContinue)) { $missing += "CODEX_CMD=$codexCmd" }
  if (-not (Get-Command $qwenCmd -ErrorAction SilentlyContinue)) { $missing += "QWEN_CMD=$qwenCmd" }
  if ($missing.Count -gt 0) {
    throw ("Missing CLI command(s): " + ($missing -join ", ") + ". Fix config/agents.conf and ensure commands are in PATH.")
  }
}

switch ($Command) {
  "create" {
    if (-not $PromptArgs -or $PromptArgs.Count -eq 0) { throw "Usage: orchestrator.ps1 create <prompt>" }
    New-OrchestratorTask -Prompt ($PromptArgs -join " ")
    break
  }
  "stats" {
    Get-OrchestratorStats
    break
  }
  default {
    Test-AgentCommands
    Start-OrchestratorAgents
    while ($true) {
      Clear-Host
      Write-Host "AI ORCHESTRATOR (PowerShell)"
      Write-Host (Get-OrchestratorStats)
      Write-Host ""
      Write-Host "[n] new task  [q] quit"
      $key = $null
      if ($Host.UI.RawUI.KeyAvailable) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character
      }
      if ($key -eq "n") {
        Write-Host ""
        $prompt = Read-Host "Enter task prompt"
        if ($prompt) { New-OrchestratorTask -Prompt $prompt | Out-Null }
      }
      if ($key -eq "q") { break }
      $refresh = [int](Get-CfgValue -Config $cfg -Key "MONITOR_REFRESH" -DefaultValue "2")
      Start-Sleep -Seconds $refresh
    }
  }
}
