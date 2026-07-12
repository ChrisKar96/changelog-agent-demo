#!/usr/bin/env bash
# Dispatch weekly-changelog once per Sunday from START to (but not including) END.
# One agent run per week — resumable, cost-bounded, idempotent (workflow skips duplicates).
set -euo pipefail

START="${START:-2026-01-04}"   # first Sunday of 2026
END="${END:-}"                 # default: next Sunday after today (UTC)
SLEEP_SECS="${SLEEP_SECS:-30}" # pause between dispatches
DRY_RUN="${DRY_RUN:-0}"
WORKFLOW="${WORKFLOW:-weekly-changelog.md}"

if [[ -z "$END" ]]; then
  # Next Sunday (or today if Sunday) in UTC — backfill finished weeks only
  today=$(date -u +%F)
  dow=$(date -u -d "$today" +%w)  # 0=Sunday
  if [[ "$dow" == "0" ]]; then
    END="$today"
  else
    END=$(date -u -d "$today +$((7 - dow)) days" +%F)
  fi
fi

echo "Backfill plan"
echo "  workflow : $WORKFLOW"
echo "  start    : $START (inclusive)"
echo "  end      : $END (exclusive — last week starts 7 days before)"
echo "  sleep    : ${SLEEP_SECS}s between runs"
echo "  dry_run  : $DRY_RUN"
echo

if ! command -v gh >/dev/null; then
  echo "gh CLI required" >&2
  exit 1
fi

# Ensure we are inside a GitHub repo with remote
if ! gh repo view >/dev/null 2>&1; then
  echo "Not in a GitHub repository (or no access). Push the demo and re-run." >&2
  exit 1
fi

d="$START"
count=0
while [[ "$d" < "$END" ]]; do
  week_end=$(date -u -d "$d +7 days" +%F)
  # Only dispatch fully completed weeks
  if [[ ! "$week_end" < "$END" && "$week_end" != "$END" ]]; then
    : # week_end >= END means this week may still be open if END is mid-week handling
  fi
  if [[ "$week_end" > "$END" ]]; then
    break
  fi

  count=$((count + 1))
  echo "[$count] Week of $d → $week_end"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  DRY_RUN: gh workflow run \"$WORKFLOW\" -f week_start=$d -f week_end=$week_end"
  else
    gh workflow run "$WORKFLOW" \
      -f week_start="$d" \
      -f week_end="$week_end"
    echo "  dispatched"
    if [[ "$SLEEP_SECS" -gt 0 ]]; then
      sleep "$SLEEP_SECS"
    fi
  fi
  d="$week_end"
done

echo
echo "Dispatched $count week(s)."
echo "Watch: gh run list --workflow \"$WORKFLOW\""
echo "Or:    gh aw status"
