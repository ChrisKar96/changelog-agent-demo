#!/usr/bin/env bash
# Print Sunday windows from START to END (exclusive end week boundary).
set -euo pipefail
START="${1:-2026-01-04}"
END="${2:-}"
if [[ -z "$END" ]]; then
  today=$(date -u +%F)
  dow=$(date -u -d "$today" +%w)
  if [[ "$dow" == "0" ]]; then END="$today"; else END=$(date -u -d "$today +$((7 - dow)) days" +%F); fi
fi
d="$START"
n=0
while [[ "$d" < "$END" ]]; do
  we=$(date -u -d "$d +7 days" +%F)
  [[ "$we" > "$END" ]] && break
  n=$((n+1))
  # Count merge commits in window for a quick activity signal
  merges=$(git log main --merges --since="${d}T00:00:00Z" --until="${we}T00:00:00Z" --oneline 2>/dev/null | wc -l | tr -d ' ')
  echo "$n  $d → $we  (merge commits: $merges)"
  d="$we"
done
echo "Total weeks: $n"
