#!/usr/bin/env bash
set -euo pipefail

input=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) input="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done

content="$(cat "$input")"
if grep -q "Fix the issues from the previous review" <<< "$content"; then
  cat > "$output" << 'EOF'
def sort_unique(items):
    return sorted(set(items))
EOF
else
  cat > "$output" << 'EOF'
def sort_unique(items):
    # BUG: returns input unchanged
    return items
EOF
fi
