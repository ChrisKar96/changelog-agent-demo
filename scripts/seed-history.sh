#!/usr/bin/env bash
# Build a fake but realistic commit history from 2026-01-05 (first Mon-ish week) to ~today.
# Uses merge commits with "Merge pull request #N" messages so the agent can treat them as PRs.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
  echo "Working tree not clean; commit or stash first (or run on fresh init)." >&2
fi

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Demo Developer}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-demo@example.com}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

commit_at() {
  local date="$1" msg="$2"
  shift 2
  # remaining args are optional file ops already done by caller
  export GIT_AUTHOR_DATE="$date"
  export GIT_COMMITTER_DATE="$date"
  git add -A
  git commit --allow-empty -m "$msg" >/dev/null
}

# Feature weeks: (week_index -> narrative). Sundays of 2026 starting 2026-01-04.
# We place commits mid-week (Wed) for each week.

PR=1

# Initial import (before first Sunday window if needed)
commit_at "2026-01-02T10:00:00Z" "chore: initial project scaffold

- package.json, src/index.js, src/cli.js, tests
- MIT license"

# Week-by-week features (Sunday starts)
# Format: sunday_date|story_slug|commit messages (||| separated feature descriptions)
WEEKS=(
  "2026-01-04|bootstrap|feat: add basic task add/list CLI|||docs: README skeleton for taskctl"
  "2026-01-11|complete|feat: implement task completion (done command)|||test: cover completeTask"
  "2026-01-18|remove|feat: add task removal (rm command)|||fix: validate numeric task ids"
  "2026-01-25|priority|feat: task priorities (high/normal/low)|||docs: document priority flags"
  "2026-02-01|tags|feat: optional tags on tasks|||refactor: extract task factory helpers"
  "2026-02-08|empty|chore: dependency bump (none) — quiet week"
  "2026-02-15|list-all|feat: list --all includes completed tasks|||test: list filters"
  "2026-02-22|errors|fix: clearer errors for missing tasks|||chore: improve CLI usage text"
  "2026-03-01|persist|feat: experimental JSON file persistence sketch|||docs: note persistence is demo-only"
  "2026-03-08|empty|chore: no user-facing changes"
  "2026-03-15|cli-help|feat: polished help command|||docs: examples in README"
  "2026-03-22|priority-cmd|feat: priority subcommand to update tasks|||test: setPriority"
  "2026-03-29|breaking|feat!: require non-empty titles (breaking validation)|||fix: trim whitespace in titles"
  "2026-04-05|ci|chore: add npm test script|||docs: contribute section"
  "2026-04-12|perf|perf: avoid copying tags array twice|||refactor: simplify listTasks filter"
  "2026-04-19|empty|chore: quiet maintenance week"
  "2026-04-26|security|fix: reject prototype-polluting keys in tags|||docs: security notes"
  "2026-05-03|ux|feat: color-free stable list format for scripts|||docs: scripting examples"
  "2026-05-10|deps|chore: document node 20+ engine requirement"
  "2026-05-17|bugfix|fix: completeTask returns updated task object|||test: regression for done"
  "2026-05-24|empty|chore: no merges this week"
  "2026-05-31|bulk|feat: document batch workflows for operators|||docs: weekly ops runbook stub"
  "2026-06-07|api|feat: export _reset for tests only|||test: isolation between cases"
  "2026-06-14|changelog-prep|docs: describe upcoming agentic weekly changelog|||chore: add discussions category note"
  "2026-06-21|polish|refactor: tidy CLI switch|||docs: FAQ"
  "2026-06-28|release|chore: bump version to 0.8.0|||docs: release notes placeholder"
  "2026-07-05|agent-ready|feat: repo ready for agentic weekly changelog demo|||docs: how the demo history was seeded"
)

# Stop creating weeks after today (2026-07-12)
TODAY_EPOCH=$(date -u -d "2026-07-12" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "2026-07-12" +%s)

for entry in "${WEEKS[@]}"; do
  IFS='|' read -r sunday slug rest <<<"$entry"
  sun_epoch=$(date -u -d "$sunday" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d" "$sunday" +%s)
  if (( sun_epoch > TODAY_EPOCH )); then
    break
  fi

  # Mid-week timestamp (Wednesday 14:00 UTC)
  wed=$(date -u -d "$sunday +3 days" +%Y-%m-%d 2>/dev/null || date -u -j -v+3d -f "%Y-%m-%d" "$sunday" +%Y-%m-%d)
  IFS='|||' read -ra PARTS <<<"$rest"
  # bash split on ||| is awkward; use mapfile
  msgs=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && msgs+=("$line")
  done < <(echo "$rest" | sed 's/|||/\n/g')

  # Create a feature branch commit then a merge commit that looks like a GitHub PR
  branch="feature/${slug}"
  git checkout -b "$branch" >/dev/null 2>&1

  i=0
  for msg in "${msgs[@]}"; do
    i=$((i + 1))
    # Touch a changelog-ish breadcrumb so the tree changes each week
    mkdir -p docs/history
    echo "- ${wed}: ${msg}" >> "docs/history/${sunday}.md"
    # Also evolve README slightly some weeks
    if [[ $i -eq 1 && "$slug" != empty* ]]; then
      echo "" >> README.md 2>/dev/null || true
    fi
    # Ensure README exists early
    if [[ ! -f README.md ]]; then
      echo "# taskctl" > README.md
      echo "Tiny task CLI used to demo weekly agentic changelogs." >> README.md
    fi
    commit_at "${wed}T1${i}:00:00Z" "$msg"
  done

  git checkout main >/dev/null 2>&1
  export GIT_AUTHOR_DATE="${wed}T18:00:00Z"
  export GIT_COMMITTER_DATE="${wed}T18:00:00Z"
  git merge --no-ff -m "Merge pull request #${PR} from demo/${branch}

${msgs[0]}" "$branch" >/dev/null
  git branch -d "$branch" >/dev/null 2>&1 || true
  PR=$((PR + 1))

  # Occasional direct commit to main (hotfix) on busy weeks
  if [[ "$slug" =~ ^(errors|breaking|bugfix|security)$ ]]; then
    echo "hotfix note for ${slug}" >> docs/history/${sunday}.md
    commit_at "${wed}T20:30:00Z" "fix: hotfix on main after #$((PR-1)) (${slug})"
  fi
done

# Final tip commit at "now"
export GIT_AUTHOR_DATE="2026-07-12T12:00:00Z"
export GIT_COMMITTER_DATE="2026-07-12T12:00:00Z"
echo "Seeded $(git rev-list --count HEAD) commits across ${#WEEKS[@]} planned weeks (PR merges #1..)."
git log --oneline | head -20
echo "..."
git log --oneline | tail -5
