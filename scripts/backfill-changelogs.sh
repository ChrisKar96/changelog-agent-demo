#!/usr/bin/env bash
# Backfill weekly changelog Discussions using Claude on your machine.
#
# Posts oldest → newest so GitHub's default "newest first" list is chronological
# with the most recent week on top. GitHub does NOT allow backdating discussion
# createdAt — titles carry the week date instead.
#
# Auth for Claude (first match wins):
#   1. `claude` CLI on PATH (Claude Code / Anthropic CLI)
#   2. ANTHROPIC_API_KEY → Messages API
#
# Auth for GitHub: `gh auth` with permission to create discussions.
#
# Usage:
#   ./scripts/backfill-changelogs.sh
#   DRY_RUN=1 ./scripts/backfill-changelogs.sh
#   START=2026-01-04 END=2026-07-12 SLEEP_SECS=2 ./scripts/backfill-changelogs.sh
#   WEEK=2026-03-29 ./scripts/backfill-changelogs.sh   # single week
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

START="${START:-2026-01-04}"
END="${END:-}"
WEEK="${WEEK:-}"
SLEEP_SECS="${SLEEP_SECS:-2}"
DRY_RUN="${DRY_RUN:-0}"
MODEL="${MODEL:-claude-sonnet-4-20250514}"
TITLE_PREFIX="${TITLE_PREFIX:-[Changelog] }"
CATEGORY_SLUG="${CATEGORY_SLUG:-announcements}"
BRANCH="${BRANCH:-main}"
MAX_LOG_BYTES="${MAX_LOG_BYTES:-120000}"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing dependency: $1"; }

need gh
need git
need date
need python3

if ! gh repo view >/dev/null 2>&1; then
  die "not in a GitHub repo (or no access). Run from the clone with gh auth."
fi

OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
OWNER="${OWNER_REPO%/*}"
NAME="${OWNER_REPO#*/}"

REPO_ID="$(gh api graphql -f query='query($o:String!,$n:String!){repository(owner:$o,name:$n){id}}' \
  -f o="$OWNER" -f n="$NAME" -q .data.repository.id)"

CATEGORY_ID="$(gh api graphql -f query='
query($o:String!,$n:String!){
  repository(owner:$o,name:$n){
    discussionCategories(first:30){nodes{id name slug}}
  }
}' -f o="$OWNER" -f n="$NAME" \
  --jq ".data.repository.discussionCategories.nodes[] | select(.slug==\"${CATEGORY_SLUG}\") | .id")"

[[ -n "$CATEGORY_ID" ]] || die "discussion category slug '${CATEGORY_SLUG}' not found (enable Discussions)"

sunday_on_or_before() {
  local d="$1" dow
  dow=$(date -u -d "$d" +%w)
  date -u -d "$d -${dow} days" +%F
}

if [[ -z "$END" ]]; then
  today=$(date -u +%F)
  END=$(sunday_on_or_before "$today")
fi

if [[ -n "$WEEK" ]]; then
  START=$(sunday_on_or_before "$WEEK")
  END=$(date -u -d "$START +7 days" +%F)
fi

for label in START END; do
  val="${!label}"
  dow=$(date -u -d "$val" +%w)
  [[ "$dow" == "0" ]] || die "$label=$val is not a Sunday (UTC)"
done

have_claude_cli=0
command -v claude >/dev/null 2>&1 && have_claude_cli=1

if [[ "$DRY_RUN" != "1" ]]; then
  if [[ "$have_claude_cli" -eq 0 && -z "${ANTHROPIC_API_KEY:-}" ]]; then
    die "need Claude: install CLI (claude on PATH) or set ANTHROPIC_API_KEY"
  fi
fi

echo "Backfill (local Claude → GitHub Discussions)"
echo "  repo     : $OWNER_REPO"
echo "  category : $CATEGORY_SLUG"
echo "  start    : $START (inclusive)"
echo "  end      : $END (exclusive week boundary)"
echo "  model    : $MODEL"
echo "  dry_run  : $DRY_RUN"
echo "  claude   : $([[ $have_claude_cli -eq 1 ]] && echo CLI || echo API)"
echo "  order    : oldest → newest (UI shows recent on top)"
echo

claude_generate() {
  local prompt tmp
  prompt=$(cat)

  if [[ "$have_claude_cli" -eq 1 ]]; then
    if claude --help 2>&1 | grep -q -- '--print'; then
      claude --print --model "$MODEL" "$prompt"
    elif claude -h 2>&1 | grep -qE -- '-p|--print'; then
      claude -p --model "$MODEL" "$prompt"
    else
      printf '%s\n' "$prompt" | claude --model "$MODEL"
    fi
    return
  fi

  tmp="$(mktemp)"
  printf '%s\n' "$prompt" >"$tmp"
  python3 - "$MODEL" "$tmp" <<'PY'
import json, os, sys, urllib.error, urllib.request

model, path = sys.argv[1], sys.argv[2]
prompt = open(path, encoding="utf-8").read()
body = {
    "model": model,
    "max_tokens": 4096,
    "messages": [{"role": "user", "content": prompt}],
}
req = urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    data=json.dumps(body).encode(),
    headers={
        "content-type": "application/json",
        "x-api-key": os.environ["ANTHROPIC_API_KEY"],
        "anthropic-version": "2023-06-01",
    },
    method="POST",
)
try:
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
except urllib.error.HTTPError as e:
    sys.stderr.write(e.read().decode("utf-8", errors="replace") + "\n")
    raise
parts = [b.get("text", "") for b in data.get("content", []) if b.get("type") == "text"]
text = "\n".join(parts).strip()
if not text:
    raise SystemExit("empty response from Anthropic API")
print(text)
PY
  local rc=$?
  rm -f "$tmp"
  return $rc
}

strip_fences() {
  BODY="$1" python3 - <<'PY'
import os
t = os.environ["BODY"].strip()
if t.startswith("```"):
    lines = t.splitlines()
    if lines and lines[0].startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    t = "\n".join(lines).strip()
print(t)
PY
}

discussion_exists() {
  local title="$1"
  TITLE="$title" OWNER="$OWNER" NAME="$NAME" python3 - <<'PY'
import json, os, subprocess
owner = os.environ["OWNER"]
name = os.environ["NAME"]
want = os.environ["TITLE"]
q = """
query($o:String!,$n:String!){
  repository(owner:$o,name:$n){
    discussions(first:100, orderBy:{field:CREATED_AT, direction:DESC}){
      nodes{ title url }
    }
  }
}
"""
proc = subprocess.run(
    ["gh", "api", "graphql", "-f", "query=" + q, "-f", "o=" + owner, "-f", "n=" + name],
    capture_output=True,
    text=True,
    check=True,
)
data = json.loads(proc.stdout)
for node in data["data"]["repository"]["discussions"]["nodes"]:
    if node["title"] == want:
        print(node["url"])
        break
PY
}

create_discussion() {
  local title="$1" body="$2"
  python3 - "$REPO_ID" "$CATEGORY_ID" "$title" "$body" <<'PY'
import json, subprocess, sys

repo_id, cat_id, title, body = sys.argv[1:5]
payload = {
    "query": """
      mutation($repo:ID!, $cat:ID!, $title:String!, $body:String!) {
        createDiscussion(input:{
          repositoryId:$repo, categoryId:$cat, title:$title, body:$body
        }) {
          discussion { url title createdAt }
        }
      }
    """,
    "variables": {
        "repo": repo_id,
        "cat": cat_id,
        "title": title,
        "body": body,
    },
}
proc = subprocess.run(
    ["gh", "api", "graphql", "--input", "-"],
    input=json.dumps(payload),
    text=True,
    capture_output=True,
)
if proc.returncode != 0:
    sys.stderr.write(proc.stderr or proc.stdout)
    sys.exit(proc.returncode or 1)
data = json.loads(proc.stdout)
if data.get("errors"):
    sys.stderr.write(json.dumps(data["errors"], indent=2) + "\n")
    sys.exit(1)
print(data["data"]["createDiscussion"]["discussion"]["url"])
PY
}

collect_week_log() {
  local week_start="$1" week_end="$2"
  {
    echo "### git log --merges"
    git log "$BRANCH" --merges \
      --since="${week_start}T00:00:00Z" --until="${week_end}T00:00:00Z" \
      --pretty=format:'%h | %ad | %an | %s%n%b%n---' --date=short || true
    echo
    echo "### git log (all, no merges)"
    git log "$BRANCH" --no-merges \
      --since="${week_start}T00:00:00Z" --until="${week_end}T00:00:00Z" \
      --pretty=format:'%h | %ad | %an | %s' --date=short || true
    echo
    echo "### name-status summary"
    git log "$BRANCH" --no-merges \
      --since="${week_start}T00:00:00Z" --until="${week_end}T00:00:00Z" \
      --name-status --pretty=format:'commit %h %s' 2>/dev/null | head -c "$MAX_LOG_BYTES" || true
    echo
  }
}

build_prompt() {
  local week_start="$1" week_end="$2" logdata="$3"
  cat <<PROMPT
You are writing a weekly changelog for the GitHub repository ${OWNER_REPO}.

Time window (UTC, half-open): [${week_start}, ${week_end})
Display title week: ${week_start}

Below is git history for default branch \`${BRANCH}\`. Merge commits that look like
"Merge pull request #N" should be treated as merged PRs.

Write a changelog body in Markdown ONLY (no surrounding code fence, no H1 title).
Use this structure:

## Highlights
## Features
## Fixes
## Breaking changes
## Chores & docs
## Stats
## Raw references

Rules:
- Human-readable; what changed and why it matters.
- Map conventional commits (feat/fix/docs/chore/perf/feat!) into sections.
- Omit empty sections except Highlights (say "No user-facing changes this week." if empty).
- Stats: counts of merge commits, non-merge commits, unique authors.
- Raw references: PR-like merges as #N — title; other commits as \`sha\` — subject.
- Keep roughly 150–600 words. No secrets.
- Do not invent PRs/commits that are not in the log.
- End with:

---
*Backfilled changelog for week of ${week_start} (window ends ${week_end}, UTC). Generated locally with Claude.*

GIT LOG:
${logdata}
PROMPT
}

d="$START"
count=0
skipped=0
posted=0

while [[ "$d" < "$END" ]]; do
  week_end=$(date -u -d "$d +7 days" +%F)
  if [[ "$week_end" > "$END" ]]; then
    break
  fi

  title="${TITLE_PREFIX}Week of ${d}"
  count=$((count + 1))
  echo "[$count] $title  (${d} → ${week_end})"

  existing="$(discussion_exists "$title" || true)"
  if [[ -n "$existing" ]]; then
    echo "  skip (exists): $existing"
    skipped=$((skipped + 1))
    d="$week_end"
    continue
  fi

  logdata="$(collect_week_log "$d" "$week_end")"
  prompt="$(build_prompt "$d" "$week_end" "$logdata")"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  DRY_RUN: would call Claude + createDiscussion"
    echo "  log preview:"
    echo "$logdata" | head -n 12 | sed 's/^/    /'
    d="$week_end"
    continue
  fi

  echo "  generating with Claude…"
  body="$(printf '%s\n' "$prompt" | claude_generate)"
  body="$(strip_fences "$body")"
  [[ ${#body} -ge 40 ]] || die "Claude returned too-short body for $d"

  echo "  posting discussion…"
  url="$(create_discussion "$title" "$body")"
  echo "  posted: $url"
  posted=$((posted + 1))

  if [[ "$SLEEP_SECS" -gt 0 ]]; then
    sleep "$SLEEP_SECS"
  fi
  d="$week_end"
done

echo
echo "Done. weeks_seen=$count posted=$posted skipped=$skipped dry_run=$DRY_RUN"
echo
echo "View newest-first:"
echo "  https://github.com/${OWNER_REPO}/discussions/categories/${CATEGORY_SLUG}"
echo
echo "Note: GitHub cannot backdate discussion timestamps. Chronological order comes"
echo "from posting oldest→newest; titles include the week date for humans."
