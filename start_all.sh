#!/usr/bin/env bash
set -euo pipefail

chmod +x orchestrator.sh agents/*.sh tools/*.sh tests/*.sh 2>/dev/null || true

if [[ ! -f "./config/agents.conf" ]]; then
  echo "config/agents.conf is missing"
  exit 1
fi

./orchestrator.sh
