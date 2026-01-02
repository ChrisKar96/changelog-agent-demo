---
description: |
  Generate a weekly changelog from merged PRs and commits on the default branch,
  then post it as a GitHub Discussions announcement.

on:
  # Every Sunday ~12:00 UTC (fixed so demos are predictable)
  schedule:
    - cron: "0 12 * * 0"
  workflow_dispatch:
    inputs:
      week_start:
        description: "Sunday YYYY-MM-DD — window start (inclusive). Leave empty for previous Sunday."
        required: false
        type: string
      week_end:
        description: "Sunday YYYY-MM-DD — window end (exclusive). Default: week_start + 7 days."
        required: false
        type: string

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
    # Keep changelogs permanently (do not auto-expire)
    # expires: false

---

# Weekly Changelog Announcement

You produce the weekly changelog for `${{ github.repository }}` and publish it as a
**GitHub Discussion** in the **Announcements** category.

## 1. Resolve the time window (UTC)

Compute `week_start` and `week_end` as follows:

1. If `workflow_dispatch` input `week_start` is set (`${{ inputs.week_start }}` is non-empty), use it.
2. Otherwise, set `week_start` to the most recent Sunday **before today** at `00:00:00 UTC`
   (if today is Sunday, use *previous* Sunday — the week that just finished).
3. If input `week_end` is set and non-empty, use it; else `week_end = week_start + 7 days` at `00:00:00 UTC`.
4. The window is half-open: **`[week_start, week_end)`**.
5. Format both as `YYYY-MM-DD`. Derive a display label: `Week of <week_start>`.

Print the resolved window at the top of your working notes.

## 2. Idempotency — do not duplicate

Before writing anything:

1. Search Discussions in this repo for an existing post whose title is exactly:

   `[Changelog] Week of <week_start>`

   (the safe-output prefix is `[Changelog] `, so the agent-supplied title should be
   `Week of <week_start>` — final title becomes `[Changelog] Week of YYYY-MM-DD`).

2. If a matching discussion already exists, **stop**. Do not create another discussion.
   Briefly note the existing discussion URL in the run log and exit successfully (noop).

## 3. Collect changes on the default branch

Default branch is `main`.

### Merged pull requests

List PRs **merged** into `main` whose `mergedAt` falls inside `[week_start, week_end)`.

For each PR capture: number, title, author login, merge timestamp, labels (if any),
and a one-line summary of the body (skip boilerplate checklists).

### Commits

List commits on `main` in the window (`git log main --since=week_start --until=week_end`
or GitHub compare/API).

- Prefer **merged PRs** as the primary signal.
- Include **direct commits** to `main` that are not already represented by those PRs
  (hotfixes, chore bumps). Skip merge commit noise if the PR is already listed.
- Ignore bot-only noise if clearly automated *and* not user-facing — unless it is a
  security-relevant dependency update (then put under Chores / Security).

If the GitHub PR API is empty (common in this demo repo, which only has merge commits
that *look* like PRs), treat commit messages matching:

`Merge pull request #N from ...`

as merged PRs, and use the subject/body of the merge and its parent commits as the PR content.

## 4. Write the changelog

Create **exactly one** discussion.

### Title

Supply title (without re-adding the prefix if the tool adds it — use the form the
create-discussion tool expects). Final visible title must be:

`[Changelog] Week of YYYY-MM-DD`

So if the tool auto-prefixes `[Changelog] `, pass only: `Week of YYYY-MM-DD`.

### Body structure (Markdown)

```markdown
## Highlights
- 2–5 bullets of the most important user-facing changes (or "No major highlights").

## Features
- …

## Fixes
- …

## Breaking changes
- … (omit section if none)

## Chores & docs
- …

## Stats
- Merged PRs: N
- Direct commits (excl. merges already counted): N
- Contributors: @a, @b

## Raw references
- #12 — title
- commit `abc1234` — subject
```

Rules:

- Write for **humans**: what changed and why it matters, not a SHA dump.
- Group conventional-commit prefixes (`feat`, `fix`, `docs`, `chore`, `perf`, `feat!`) into the sections above.
- Treat `feat!` / "BREAKING" as **Breaking changes**.
- If the week is empty: still post, with Highlights = "No user-facing changes this week." and Stats zeros.
- Keep the body concise (roughly 150–600 words). No secrets, no internal tokens.

## 5. Publish

Use the **create-discussion** safe output:

- category: **announcements** (must match repo Discussions category)
- one discussion only (`max: 1`)
- body length at least ~80 characters of real content

Do **not** edit existing discussions. Do **not** open issues or PRs.

## 6. Working method

1. Resolve dates.
2. Idempotency check.
3. Gather PRs/commits with tools (`gh`, GitHub MCP, `git log`).
4. Draft the body.
5. Emit create-discussion.
6. In a collapsed footer of the discussion body, list the main queries/commands you ran.
