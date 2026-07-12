---
description: |
  Generate a weekly changelog from merged PRs and commits on the default branch
  for the week that just ended, then post it as a GitHub Discussions announcement.
  Historical backfill is done locally (scripts/backfill-changelogs.sh + Claude).

on:
  schedule:
    - cron: "0 12 * * 0"   # every Sunday 12:00 UTC
  workflow_dispatch:         # manual "run for last completed week"

# Agent stays read-only. Writes go through safe-outputs only.
# copilot-requests: write bills org Copilot via GITHUB_TOKEN (org policy required).
permissions:
  contents: read
  issues: read
  pull-requests: read
  discussions: read
  actions: read
  copilot-requests: write

engine: copilot

max-ai-credits: 50
timeout-minutes: 20

network: defaults

tools:
  github:
    toolsets: [default, discussions]
    min-integrity: none
  bash:
    - "*"

safe-outputs:
  create-discussion:
    title-prefix: "[Changelog] "
    category: announcements
    max: 1
    min-body-length: 80

---

# Weekly Changelog Announcement

You produce the weekly changelog for `${{ github.repository }}` and publish it as a
**GitHub Discussion** in the **Announcements** category.

This workflow covers **only the week that just finished**. Historical weeks are
backfilled separately with `scripts/backfill-changelogs.sh` (local Claude).

## 1. Resolve the time window (UTC)

1. Let `today` be the current UTC date.
2. Set `week_end` to the most recent Sunday on or before `today` at `00:00:00 UTC`.
   - If today is Sunday (scheduled run), `week_end` is **today** (the week that just closed).
3. Set `week_start = week_end − 7 days`.
4. Window is half-open: **`[week_start, week_end)`**.
5. Display label: `Week of <week_start>` (`YYYY-MM-DD`).

Print the resolved window in your working notes.

## 2. Idempotency — do not duplicate

Before writing anything:

1. Search Discussions for an existing post whose final title is exactly:

   `[Changelog] Week of <week_start>`

   (safe-output prefix is `[Changelog] `; pass title `Week of <week_start>` if the
   tool adds the prefix for you.)

2. If it exists, **stop**. Do not create another discussion.

## 3. Collect changes on the default branch

Default branch is `main`.

### Merged pull requests

List PRs **merged** into `main` with `mergedAt` in `[week_start, week_end)`.

Capture: number, title, author, merge time, labels, one-line body summary.

### Commits

List commits on `main` in the window.

- Prefer **merged PRs** as the primary signal.
- Include **direct commits** not already covered by those PRs.
- If the PR API is empty but git has `Merge pull request #N from …` commits,
  treat those as merged PRs.

## 4. Write the changelog

Create **exactly one** discussion.

### Title

Final visible title must be: `[Changelog] Week of YYYY-MM-DD`

### Body structure

```markdown
## Highlights
## Features
## Fixes
## Breaking changes
## Chores & docs
## Stats
## Raw references
```

Rules:

- Human-readable; what changed and why it matters.
- Map conventional-commit prefixes into sections; `feat!` → Breaking changes.
- Empty week: still post, Highlights = "No user-facing changes this week."
- ~150–600 words. No secrets.
- Collapsed footer listing main queries/commands you ran.

## 5. Publish

Use **create-discussion** only (category **announcements**, max 1).
Do not edit existing discussions. Do not open issues or PRs.
