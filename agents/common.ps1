$ErrorActionPreference = "Stop"

$Script:AgentScriptDir = Split-Path -Parent $PSCommandPath
$Script:ProjectRoot = Split-Path -Parent $Script:AgentScriptDir
$Script:Workspace = Join-Path $Script:ProjectRoot "workspace"
$Script:ConfigFile = Join-Path $Script:ProjectRoot "config/agents.conf"

function Read-AgentConfig {
  if (-not (Test-Path $Script:ConfigFile)) {
    throw "Config not found: $Script:ConfigFile"
  }
  $cfg = @{}
  foreach ($line in Get-Content -LiteralPath $Script:ConfigFile) {
    $trim = $line.Trim()
    if (-not $trim -or $trim.StartsWith("#")) { continue }
    if ($trim -notmatch "^[A-Za-z_][A-Za-z0-9_]*=") { continue }
    $eq = $trim.IndexOf("=")
    $k = $trim.Substring(0, $eq).Trim()
    $v = $trim.Substring($eq + 1).Trim()
    if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Trim('"') }
    if ($v.StartsWith("'") -and $v.EndsWith("'")) { $v = $v.Trim("'") }
    if ($v -match "^([^#]+)#") { $v = $Matches[1].Trim() }
    $cfg[$k] = $v
  }
  return $cfg
}

function Get-CfgValue {
  param(
    [hashtable]$Config,
    [string]$Key,
    [string]$DefaultValue
  )
  if ($Config.ContainsKey($Key) -and $null -ne $Config[$Key] -and "$($Config[$Key])".Trim() -ne "") {
    return "$($Config[$Key])"
  }
  return $DefaultValue
}

function Initialize-Workspace {
  New-Item -ItemType Directory -Force -Path (Join-Path $Script:Workspace "tasks") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $Script:Workspace "completed") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $Script:Workspace "logs") | Out-Null
}

function Write-AgentLog {
  param(
    [string]$Agent,
    [string]$Level,
    [string]$Message
  )
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$ts] [$Agent] [$Level] $Message"
  Add-Content -LiteralPath (Join-Path $Script:Workspace "logs/$Agent.log") -Value $line -Encoding UTF8
}

function Get-TasksByStatus {
  param([string]$Status)
  $tasksRoot = Join-Path $Script:Workspace "tasks"
  if (-not (Test-Path $tasksRoot)) { return @() }
  $out = @()
  foreach ($dir in Get-ChildItem -LiteralPath $tasksRoot -Directory -ErrorAction SilentlyContinue) {
    if (-not $dir.Name.StartsWith("task_")) { continue }
    $statusFile = Join-Path $dir.FullName "status.txt"
    if (-not (Test-Path $statusFile)) { continue }
    $s = (Get-Content -LiteralPath $statusFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    if ($s -eq $Status) { $out += $dir.FullName }
  }
  return $out
}

function Set-TaskStatus {
  param([string]$TaskDir, [string]$Status)
  Set-Content -LiteralPath (Join-Path $TaskDir "status.txt") -Value $Status -Encoding UTF8
}

function Get-TaskIteration {
  param([string]$TaskDir)
  $f = Join-Path $TaskDir "iteration"
  if (-not (Test-Path $f)) { return 0 }
  $v = Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $v) { return 0 }
  return [int]$v
}

function Increment-TaskIteration {
  param([string]$TaskDir)
  $i = (Get-TaskIteration -TaskDir $TaskDir) + 1
  Set-Content -LiteralPath (Join-Path $TaskDir "iteration") -Value $i -Encoding UTF8
  return $i
}

function Set-TaskStartTime {
  param([string]$TaskDir)
  [int][double]::Parse((Get-Date -UFormat %s)) | Set-Content -LiteralPath (Join-Path $TaskDir "start_time") -Encoding UTF8
}

function Clear-TaskStartTime {
  param([string]$TaskDir)
  Remove-Item -LiteralPath (Join-Path $TaskDir "start_time") -Force -ErrorAction SilentlyContinue
}

function Test-TaskTimeout {
  param([string]$TaskDir, [int]$TimeoutSeconds)
  $f = Join-Path $TaskDir "start_time"
  if (-not (Test-Path $f)) { return $false }
  $start = [int](Get-Content -LiteralPath $f | Select-Object -First 1)
  $now = [int][double]::Parse((Get-Date -UFormat %s))
  return (($now - $start) -gt $TimeoutSeconds)
}

function Acquire-TaskLock {
  param([string]$TaskDir)
  $lockDir = Join-Path $TaskDir ".lock"
  try {
    New-Item -ItemType Directory -Path $lockDir -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Release-TaskLock {
  param([string]$TaskDir)
  Remove-Item -LiteralPath (Join-Path $TaskDir ".lock") -Force -ErrorAction SilentlyContinue
}

function Invoke-ModelCli {
  param(
    [string]$CommandPath,
    [string[]]$Arguments
  )
  $process = Start-Process -FilePath $CommandPath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
  return $process.ExitCode
}

Initialize-Workspace
