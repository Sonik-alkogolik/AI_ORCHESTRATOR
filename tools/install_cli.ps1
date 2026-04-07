$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "orchestrator.ps1") install
