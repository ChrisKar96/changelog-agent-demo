# changelog-agent-demo

Demo repository for **weekly changelogs via GitHub Agentic Workflows (`gh aw`)**.

Each Sunday an agent:

1. Collects merged PRs + commits on `main` for the previous week (`[Sunday, next Sunday)` UTC)
2. Writes a human-readable changelog
3. Posts it as a **Discussions → Announcements** post titled `[Changelog] Week of YYYY-MM-DD`

The same workflow accepts `workflow_dispatch` inputs so you can **backfill every week since 2026-01-04** one run at a time.

## What’s in the box

| Path | Purpose |
|------|---------|
| `src/` | Tiny `taskctl` Node CLI (dummy product history) |
| `docs/history/` | Per-week breadcrumb notes created by the seed |
| `.github/workflows/weekly-changelog.md` | Agentic workflow **source** (edit this) |
| `.github/workflows/weekly-changelog.lock.yml` | Compiled Actions workflow (**generated**) |
| `scripts/seed-history.sh` | Rebuilds fake 2026 commit/PR history |
| `scripts/backfill-changelogs.sh` | **Local Claude** backfill → Discussions (oldest→newest) |
| `scripts/list-weeks.sh` | Lists week windows + merge counts |

History is **synthetic**: merge commits look like `Merge pull request #N from demo/...` so the agent has PR-shaped signal even without real GitHub PRs.

## Prerequisites

1. **GitHub CLI** `gh` + extension:
   ```bash
   gh extension install github/gh-aw
   ```
2. **Org Copilot for Actions** (this demo uses org-billed Copilot):
   - Repo under an org with Copilot
   - Org policy: **Allow use of Copilot CLI billed to the organization**
   - Workflow permission `copilot-requests: write` (already set in the frontmatter)
3. **Discussions enabled** on the repo, with a category slug **`announcements`**
   (Settings → General → Features → Discussions; create/rename category if needed)
4. Actions enabled on the repo

> Personal accounts / no org billing: either move the repo under a qualifying org, or switch `engine` / auth to a PAT (`COPILOT_GITHUB_TOKEN`) or a third-party engine + API key. See [gh-aw billing](https://github.github.com/gh-aw/reference/billing/).

## Live demo repo

**https://github.com/ChrisKar96/changelog-agent-demo**

Already done on GitHub:
- Public repo pushed (`main`)
- Discussions **enabled** (category **Announcements** / slug `announcements`)
- Workflows registered: `Weekly Changelog Announcement`, `Agentic Maintenance`

Still required for a successful agent run:
- **Copilot billing**: this workflow uses `permissions.copilot-requests: write` (org-billed Copilot via `GITHUB_TOKEN`). On a **personal** repo, either:
  1. Transfer the repo under an org with Copilot + policy **Allow use of Copilot CLI billed to the organization**, or
  2. Add secret `COPILOT_GITHUB_TOKEN` (PAT with Copilot access) for individual billing
- Confirm Actions are allowed for the account

## Two paths: forward vs backfill

| | **Ongoing (Copilot / gh-aw)** | **Backfill (local Claude)** |
|--|------------------------------|-----------------------------|
| When | Every Sunday + manual dispatch | Once, for 2026 → last week |
| How | `.github/workflows/weekly-changelog.md` | `scripts/backfill-changelogs.sh` |
| Model | Org-billed Copilot in Actions | `claude` CLI or `ANTHROPIC_API_KEY` |
| Order | Natural (each week posts when due) | **Oldest → newest** so the list is chronological |

### Can we backdate announcement timestamps?

**No.** The GitHub Discussions API does not accept a custom `createdAt`. Every post
gets “now” as its creation time.

**How we still get chronological order (recent on top):**

1. Backfill posts **oldest week first, newest last**.
2. The Announcements list sorts by **created time, newest first**.
3. After the loop finishes, the most recent week is on top; older weeks sit below.
4. Titles are `[Changelog] Week of YYYY-MM-DD` so humans always know the real week.

Do **not** post newest-first during backfill, or the list will be reversed.

Optional extra: a single index discussion linking all weeks (not included by default).

## Quick start (this repo already seeded)

```bash
# 1. Create GitHub repo + push (from this directory)
gh repo create changelog-agent-demo --public --source=. --remote=origin --push

# 2. Enable Discussions in the GitHub UI, ensure category "Announcements" (slug: announcements)

# 3. Confirm workflow is visible
gh workflow list

# 4. Plan weeks + dry-run backfill (no Claude/API calls that post)
./scripts/list-weeks.sh
DRY_RUN=1 ./scripts/backfill-changelogs.sh

# 5. Backfill with local Claude (needs `claude` on PATH or ANTHROPIC_API_KEY)
#    Single week first:
WEEK=2026-03-29 ./scripts/backfill-changelogs.sh
#    Full range (default 2026-01-04 → last completed Sunday):
./scripts/backfill-changelogs.sh

# 6. Going forward: Sunday cron uses Copilot agentic workflow automatically
#    Manual run for last week only:
gh workflow run weekly-changelog.md
gh run watch
```

### Claude auth for backfill

```bash
# Option A — Claude Code / CLI
# install from Anthropic, then ensure `claude` is on PATH

# Option B — API key
export ANTHROPIC_API_KEY=sk-ant-...
# optional: MODEL=claude-sonnet-4-20250514
```


## Editing the agent

1. Edit `.github/workflows/weekly-changelog.md` (frontmatter + prompt)
2. Recompile:
   ```bash
   gh aw compile
   ```
3. Commit **both** `.md` and `.lock.yml`

## Cost controls

- `max-ai-credits: 50` per run (~$0.50 AIC estimate) — raise/lower as needed
- Backfill is **sequential** (`SLEEP_SECS`, default 30) so you do not stampede Actions/Copilot
- Re-runs are **idempotent**: the agent skips if `[Changelog] Week of …` already exists
- Preview cost: `gh aw forecast` (if available in your CLI version)

## How the time window works

```
week_start = Sunday 00:00 UTC (inclusive)
week_end   = next Sunday 00:00 UTC (exclusive)

schedule (Sundays): previous Sunday → this Sunday
dispatch:           explicit week_start / week_end inputs
```

## Recreate dummy history from scratch

```bash
# WARNING: rewrites git history — only for local demos
rm -rf .git
git init -b main
# restore non-history files if needed, then:
./scripts/seed-history.sh
gh aw compile
```

## License

MIT
