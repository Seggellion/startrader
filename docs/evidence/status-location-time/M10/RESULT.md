# M10 — Release closure and safe removal of the task worktree

Recorded 2026-11-16 (UTC), immediately **before** the worktree removal. This file is the last commit made from the task worktree. The post-removal verification (worktree gone, branches deleted, `main` = GitHub, production unchanged) is reported in the final project report, because nothing can be committed from a worktree after it is removed. By decision C2 no other checkout of `main` exists to commit from.

## Preconditions

| Requirement | State |
|---|---|
| M09 PASS, monitoring complete, no rollback in progress | ✅ `M09/RESULT.md` (9 h 26 min observed; no release-specific regression) |
| All implementation commits in `main` and GitHub | ✅ `main` = GitHub `main` = `3d7e1dc` before closeout; `git rev-list main..claude/status-location-time-repair` lists only the documentation commits being landed now |
| Production corresponds to the code | ✅ Heroku v179 = `3d7e1dc` |
| Closeout commits are documentation only | ✅ `git diff --name-only 3d7e1dc <closeout>` lists only `docs/evidence/status-location-time/**` (decision C1) |
| Evidence preserved in `main` history before removal | ✅ discovery, playbook, `DECISIONS.md`, `M00`–`M10` results, release packet, deployment and monitoring evidence, read-only SQL used |
| Unrelated work untouched | ✅ main checkout (`/home/dusti/startrader`, branch `codex/restore-bare-jump`, its modified `cors.rb` and untracked files), the worktrees `friendly-leakey-963229`, `startrader-interdict-login-d01ee6`, `tmp/maidenbot-cors-20261106/release-worktree`, the branches of other sessions, and the shared test database's other data |

## Task-owned worktree

* Path: `/home/dusti/startrader/.claude/worktrees/startrader-discovery-fa1f6d`, created 2026-11-15 17:15:53 for this Claude session. Branch at closeout: `claude/status-location-time-repair`. Its original branch `claude/startrader-discovery-fa1f6d` (`4f42a56`) holds no unique commits.
* Status: no tracked modifications and **no untracked files**. Ignored, task-generated content only (every item is newer than the worktree's creation and produced by this project's test runs):

| Item | Disposition |
|---|---|
| `tmp/slt/*` (59 enumerated logs, identity lists, read-only SQL snippets, schema snapshots) | deleted individually. Their results are recorded in `M00`–`M09` (counts, identity comparisons, migration outputs). |
| `log/test.log`, `log/test.log.0` (~106 MB test logs) | deleted individually; reproducible |
| `tmp/local_secret.txt` (Rails-generated local test secret for this worktree only; the main checkout has its own) | deleted individually |
| `app/assets/builds/tailwind.css` (generated build output) | deleted individually; reproducible |
| `tmp/cache/`, `tmp/orbital-assets-cache/` (generated caches) | removed with the worktree directory by `git worktree remove` (not separately deleted) |

## Removal procedure (no force)

Run from `/home/dusti` (outside the target worktree), in a single shell invocation, because the session's working directory is the worktree itself:

1. `git -C /home/dusti/startrader worktree remove /home/dusti/startrader/.claude/worktrees/startrader-discovery-fa1f6d` (no `--force`)
2. `git -C /home/dusti/startrader branch -d claude/status-location-time-repair` (fully merged into `main`)
3. `git -C /home/dusti/startrader branch -d claude/startrader-discovery-fa1f6d` (this session's original branch; an ancestor of `main`, no unique commits)
4. Verify: `git worktree list` no longer shows the path; `main` = `git ls-remote origin main`; Heroku is still v179; the main checkout's `git status` is unchanged from M00.

Never used: `git reset --hard`, `git clean`, `git worktree remove --force`, recursive deletion of a workspace.

## Retained deliberately

* Shared isolated test database `star_trader_terminal_test` (profile `.env.terminal-test`, owner's file): left in place. Its schema now includes this project's migrations, and `db:prepare` reconciles it for any later project.
* Production backup `b006` and earlier backups.
* `.byebug_history` (tracked; decision S3 leaves it for owner review).
* Harness task-output files under `/tmp/claude-1000/…/tasks/` belong to the Claude Code harness, not the repository.

## Outstanding items (owner follow-ups)

1. **Production RabbitMQ outage** (pre-existing since 2026-11-05 15:14 UTC; 4 prod arrival events pending). Not addressed by this project.
2. Changed status and Jump paths had **not yet been exercised by live traffic** during monitoring. Watch the first real requests: `warnings`, `location_resolution`, and the `jump_not_at_gateway` and 404 unknown-shard responses.
3. Migrate the StarBitizen bot to `ship.remaining_travel_seconds` if it should show paused countdowns (Q6 kept `ship.time_remaining` unchanged; R-6 fails by design).
4. New live shards must now be registered in Admin › Shards before their players can sync (Q3).
5. Protected journey 5071 is still paused; owner review only.
6. Cosmetic: rename the audit key `ships_status_locked_while_idle`, which still uses the pre-M03 definition.
7. Deferred findings: F-07, F-08, F-12 (Q7), F-14, F-16.
8. The main checkout's v177 documentation commits (`313f17a`, `6326f24`) and the unreleased interdiction branches remain outside `main` by decision P0.
