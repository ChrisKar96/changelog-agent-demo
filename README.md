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
| `scripts/backfill-changelogs.sh` | Dispatches one run per Sunday window |
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

## Quick start (this repo already seeded)

```bash
# 1. Create GitHub repo + push (from this directory)
gh repo create changelog-agent-demo --public --source=. --remote=origin --push

# 2. Enable Discussions in the GitHub UI, ensure category "Announcements" (slug: announcements)

# 3. Confirm workflow is visible
gh workflow list

# 4. Dry-run backfill plan
./scripts/list-weeks.sh
DRY_RUN=1 ./scripts/backfill-changelogs.sh

# 5. Test a single week first (pick a busy one)
gh workflow run weekly-changelog.md \
  -f week_start=2026-03-29 \
  -f week_end=2026-04-05

gh run watch   # or: gh aw logs weekly-changelog

# 6. Full backfill (one dispatch every 30s)
./scripts/backfill-changelogs.sh

# 7. Going forward: the Sunday cron runs automatically
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
