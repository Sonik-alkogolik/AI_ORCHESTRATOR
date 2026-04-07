#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT/workspace"

mkdir -p "$WORKSPACE/tasks" "$WORKSPACE/completed" "$WORKSPACE/logs"
rm -rf "$WORKSPACE/tasks"/* "$WORKSPACE/completed"/*
find "$WORKSPACE/logs" -type f -name "*.log" -delete
echo "workspace cleaned"
