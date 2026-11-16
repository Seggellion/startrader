# Release packet — status / location / time repair

Prepared 2026-11-16 (UTC). No secrets are stored here. Decision references: `../DECISIONS.md`.

## Identity

| Item | Value |
|---|---|
| Production app | Heroku `star-trader` (region us, heroku-24, `heroku-postgresql:essential-0`, web 1 + worker 1) |
| Current production | **v178**, source `c73b582fd76d…` (= `heroku/main` = GitHub `production-v178`) |
| GitHub `main` | `4f42a566b73f…` (unprotected; history merged by PR) |
| Release candidate | `claude/status-location-time-repair`. The tested code commit is `b60e97b`; the final RC SHA is the evidence commit on top of it, with an identical code tree (verified with `git diff b60e97b <RC> -- app lib config db test Gemfile Gemfile.lock` → empty). |
| Ancestry | the RC contains `c73b582` (production) **and** `4f42a56` (GitHub main), so both pushes are **fast-forward, no force** |
| Deploy mechanism (verified from release history v173–v178: "Deploy <sha>" by the owner) | `git push heroku <RC>:main` |

## What ships

1. **This project (M01–M07):** admin user overview and audit task; Jump gateway rule (Q2) and membership check; one location writer, narrowed status locking with the stale-origin guard (Q1, N-01), arrival lands the player, delivery guard; status degrade-not-abort (F-18, F-05), normalized shard identity with **unknown shards refused** (Q3), audited reassignment (Q4), path selection, bounded retries; additive `_at_unix` and paused-aware keys (Q6) and zone-labelled admin times; tick and user route containment, move route removed, `byebug` dev/test only (S1–S3).
2. **From GitHub `main` (never deployed before), brought in by decision P0:** `61331ac` (the `ShardUser` `JsonStoreCoder`, which reads native and string JSON and writes the same format as today; menu-item and contact-message fixes; buy/sell shard lookup by id) and `5576bb0` (a duplicate admin script include removed). 15 files, ~97 lines, all covered by the green suite.

## Expected response and behavior changes

| Endpoint | Change | Client impact |
|---|---|---|
| `POST /api/status` | 400/422 → **200 with warnings** for an unresolved location or a name collision; **404** for an unknown `shard_uuid` (Q3); new keys `warnings`, `location_resolution`, `server_time_at_unix`, `travel.arrival_at_unix`, `ship.remaining_travel_seconds`, `ship.arrival_at_unix`; idle ships with travel history accept location again | more permissive, except **a new live shard must be registered in Admin › Shards first** |
| `POST /api/gate_travel` | **422 `jump_not_at_gateway`** for a named gateway the ship is not at (Q2); **422 `shard_membership_missing`**; new `arrival_at_unix`, `server_time_at_unix` | the bot's bare jumps are unaffected |
| `POST /api/travel`, `GET /api/location/:id` | new `arrival_at_unix`, `server_time_at_unix` | additive |
| `GET /api/commodities` | new `"updated-at-unix"` | additive |
| `POST /api/increment_tick`, `/api/set_tick` | **401 without secret**; `set_tick` → 501 | no in-repo caller |
| `GET/POST /users` | **admin only**, minimal fields | no in-repo caller; previously 500 for everyone |
| `POST /api/user_ships/:id/move` | **removed** (404) | was broken |
| RabbitMQ `ShipArrival` | **unchanged** (13 positional fields) | none |

## Migrations, in order (each applied once, by `rails db:migrate`)

| Version | Change | Lock and duration expectation | Old-code compatibility |
|---|---|---|---|
| `20261024170000` | `user_ship_cargos.buy_price/sell_price` numeric(10,2) → (15,2) | brief `ALTER TABLE` on a small table | yes |
| `20261116010000` | add nullable `shard_users.location_updated_at`, `location_source` | metadata only | yes (old code ignores the columns) |
| `20261116020000` | unique index `lower(btrim(channel_uuid))` on `shards`, built `CONCURRENTLY` | no write lock; 6 rows | yes. **Precondition:** re-run the casefold duplicate count immediately before migrating; it must be 0. |

**Why a maintenance window is needed:** the Procfile has no `release:` phase, and `heroku run` executes on the *current* slug. The migrations can therefore only run after the new slug is deployed. The new code writes `location_updated_at` and `location_source`, so it must not serve traffic or process arrivals before migration. v172 used the same sequence ("maintenance/quiescence … restored web/worker").

## Rollout sequence (M09)

0. **Preflight, read-only.** Confirm release v178, slug and source `c73b582`, formation web 1 / worker 1, `TickControl` running with `failure_count` 0, the casefold shard duplicate count = 0, unfinished journeys (expected: 1 paused, `arrival_tick = 0`), the migration list, and the M00 metrics.
1. **Backup.** `heroku pg:backups:capture -a star-trader`; confirm it shows Completed. Restorability is verified per the owner's chosen method.
2. **GitHub.** Fast-forward local `main` to the RC (`git fetch . <RC>:main`, which refuses a non-fast-forward), then `git push origin <RC>:main` (no force). Verify `git ls-remote origin main` = RC.
3. `heroku maintenance:on -a star-trader`, then `heroku ps:scale worker=0 -a star-trader` (quiesce arrivals and the tick chain).
4. `git push heroku <RC>:main`, which builds release **v179**. Verify the release description says "Deploy <RC short sha>".
5. `heroku run rails db:migrate -a star-trader`. Verify the three versions are present in `schema_migrations`.
6. `heroku ps:scale worker=1 -a star-trader`, then `heroku maintenance:off -a star-trader`. Verify the dynos are up on v179.
7. **Verification and monitoring** (≥ 30 min): `/up`; read-only `/api/location/:id` GETs; `heroku run rails status_location:audit` (READ ONLY transaction) compared with the M00 metrics; admin overview rendered for sample users inside a read-only transaction; tick heartbeat advancing and `failure_count` 0; no `5xx` or `status_location`/`gate_request_failed` error spikes; arrival events delivered; no duplicate unfinished journeys.

## Rollback

| Trigger | Action |
|---|---|
| Failed migration | stay in maintenance; inspect. The additive migrations are individually reversible (`rails db:rollback`), but **prefer rolling back the application** (`heroku rollback v178 -a star-trader`) while keeping compatible columns. If the index fails on duplicates, do not merge shards; roll back the application and reconcile by hand. |
| Error-rate rise, stopped tick chain, duplicate unfinished journeys, wrong Rabbit environment, unauthorized access | `heroku rollback v178 -a star-trader` (v178's code tolerates the added columns and index), then verify ticks and jobs, record the incident, and stop M10 cleanup |
| Never | destructive reverse migrations during an incident, player relocation, manual tick changes |

## Success thresholds

0 new `5xx` classes; status error rate not above the M00 baseline (which was inconclusive, so any sustained 5xx is a trigger); tick heartbeat within 30 s; `failure_count` 0; unfinished journeys unchanged except for natural progress; the audit task runs and reports `transaction_read_only: on`.

## Post-release record (completed 2026-11-16)

| Item | Observed |
|---|---|
| GitHub `main` | `3d7e1dc2eed92d1f0a482d3e77951f698a5ec2ab` (fast-forward from `4f42a56`) |
| Local `main` branch | `3d7e1dc` (fast-forward from `fecb49f`; branch reference only; see M10 about the physical main checkout) |
| Production | Heroku `star-trader` **v179** "Deploy 3d7e1dc2", released 05:10:41 UTC |
| Backup | `b006`, Completed 05:06:58 UTC (623.46 KB) |
| Migrations | `20261024170000`, `20261116010000`, `20261116020000` applied (exit 0), confirmed via `schema_migrations` |
| Maintenance window | 05:08:02 → 05:12:13 UTC (4 min 11 s); game-clock pause ~05:07:51 → ~05:15:00 UTC |
| Tests | merged tree 675 runs, 7073 assertions, 0 failures/errors; reproductions: only R-6 fails, by design (Q6) |
| API verification | `/up`, `/`, `/api/commodities` 200; `updated-at-unix` integer; live policy: 1 of 229 ships blocked (the in-flight one), N-01 resolved |
| Admin verification | overview rendered for 15 real users, 0 errors (READ ONLY transaction); authenticated browser session not exercised (read-only smoke scope) |
| Monitoring | 9 h 26 min; no release-specific regression; tick cadence ~24 s/tick, unchanged; watchdog never recovered |
| Outstanding | **production RabbitMQ outage (pre-existing since 2026-11-05)**; changed status and Jump paths not yet exercised by live traffic |
| Rollback readiness | `heroku rollback v178 -a star-trader` remains valid (v178 tolerates the additive schema); backup `b006` available; not triggered |
