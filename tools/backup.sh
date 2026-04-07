#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT/workspace"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$ROOT/workspace_backup_$STAMP"

cp -R "$WORKSPACE" "$BACKUP_DIR"
echo "$BACKUP_DIR"
