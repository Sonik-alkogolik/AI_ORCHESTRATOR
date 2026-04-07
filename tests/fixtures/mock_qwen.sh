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

prompt="$(cat "$input")"
if grep -q "BUG: returns input unchanged" <<< "$prompt"; then
  cat > "$output" << 'EOF'
[LOGIC] Function does not sort and deduplicate.
Recommendation: return sorted(set(items)).
EOF
else
  echo "OK" > "$output"
fi
