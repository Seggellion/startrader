# M09 — Merge to main, publish GitHub, deploy production and verify

**Verdict: PASS (G5) for all release-specific criteria, 2026-11-16.** Closing check at 14:38 UTC. The owner GO, the backup method and the read-only smoke scope were recorded first (decisions R1–R4).

| Category | Items |
|---|---|
| New production regressions | **None observed** |
| Known pre-existing problems | **Production RabbitMQ outage**: no prod `ShipArrival` delivered since 2026-11-05 15:14 UTC; 4 prod events still pending (`arrival_delivery_failed` keeps logging). **Outstanding operational issue; delivery is not healthy.** Not caused or changed by v179 (no broker code or config in the release). |
| Accepted operational exceptions | ~7-minute game-clock pause during the release (05:07:51 → ~05:15:00 UTC; maintenance window 4 min 11 s). The documentation-only closeout commit after the deployed SHA (see M10). |
| Unverified behavior | **No live player traffic has exercised the changed paths.** In the ~9.5 h after release no `shard_users` or `user_ships` row was written, no receipt completed and no arrival event was created; the only API traffic was `GET /api/ships`. Status and Jump behavior is verified by the 675-run green suite, the reproductions, and read-only live policy evaluation, **not yet by real requests**. |

## Final identities

| Item | Value |
|---|---|
| Release candidate / deployed source | **`3d7e1dc2eed92d1f0a482d3e77951f698a5ec2ab`** |
| Local `main` | `3d7e1dc` (fast-forwarded from `fecb49f` with `git fetch . 3d7e1dc:main`, which refuses a non-fast-forward. `main` is not checked out in any worktree, so no working files were touched.) |
| GitHub `main` | `3d7e1dc` (`git push origin 3d7e1dc:refs/heads/main`, `4f42a56..3d7e1dc`, fast-forward, no force; verified with `git ls-remote`) |
| Heroku `star-trader` | **release v179 "Deploy 3d7e1dc2"**, created 2026-11-15 22:10:41 −07:00 (05:10:41 UTC); `heroku/main` `c73b582..3d7e1dc` (fast-forward) |
| Previous release (rollback target) | v178, `c73b582` |
| Backup | **`b006`** captured 2026-11-16 05:06:57 UTC, **Completed** 05:06:58 UTC, 623.46 KB |
| GitHub → Heroku auto-deploy | none observed: the release list was still v178 after the GitHub push, so there was no double deploy |

## Executed sequence (UTC)

| Time | Step | Result |
|---|---|---|
| 05:02:58 | Preflight (read-only): v178/`c73b582`, web 1 + worker 1 up, maintenance off; casefold shard duplicates **0**, unfinished journeys 1 (paused, sentinel), tick running, `failure_count` 0, last tick 18 s ago, failed jobs 0 | ✅ (`preflight_before.txt`) |
| — | **Pre-existing anomaly found:** the prod RabbitMQ broker has delivered nothing since 2026-11-05 15:14 (4 prod arrival events pending, `RabbitmqConnection::UnavailableError`, ~3000 attempts each; the dev broker delivers). The owner chose to proceed and treat it as a known baseline. | owner follow-up |
| 05:06:57 | `heroku pg:backups:capture` | `b006` Completed |
| ~05:07 | local `main` fast-forward; GitHub push | `3d7e1dc` on both |
| 05:08:02 | `heroku maintenance:on`; `heroku ps:scale worker=0` | done |
| 05:10:41 | `git push heroku 3d7e1dc:refs/heads/main` | **Released v179**; "Verifying deploy... done" |
| ~05:11:30 | `heroku run rails db:migrate --exit-code` | exit 0: `20261024170000` (6.4 ms), `20261116010000` (4.3 ms), `20261116020000` (22.7 ms) |
| 05:12:13 | `heroku ps:scale worker=1`; `heroku maintenance:off` | web.1 and worker.1 up on v179. **Maintenance window: 4 min 11 s.** |
| 05:15:06 | Tick chain resumed (811565 → 811566), then a steady cadence (last-completed age 3 s, `failure_count` 0) | ✅ |

**Tick pause note:** the game clock did not advance from 05:07:51 (worker scaled down) to ~05:15:00, about 7 minutes. That is longer than the maintenance window because each dyno boot spends ~30 s timing out against the unreachable prod broker before the worker picks up the overdue `TickJob`. Ticks are counters and journeys are tick-based, so no journey timing was lost: every journey simply ran about 7 minutes longer in wall time, as during any planned quiescence. The game was not otherwise harmed.

## Live verification (read-only, decision R3)

| Check | Result |
|---|---|
| `GET /up`, `GET /`, `GET /api/commodities` | 200 / 200 / 200; `"updated-at-unix"` present as an integer |
| Post-release DB check (read-only) | `latest_migration = 20261116020000`; both instrumentation columns present; casefold duplicates 0; unfinished 1; no duplicate unfinished journeys; failed jobs 0 (`postflight_after.txt`) |
| `heroku run rails status_location:audit` (new task, READ ONLY transaction) | exit 0, `transaction_read_only: on`. Pairs: 163 aligned / 64 diverged (all multi-ship players, M07) / 1 unknown / 1 interdicted. Shard variant groups 0. Storage: 154 string + 1 NULL, 0 coordinates. Identical to the M00 baseline, as expected immediately after a code-only release. (`audit_after_release.json`) |
| Live policy check (`rails runner`, READ ONLY transaction) | of 229 ships, **only 1 is blocked from status location updates** (the in-flight paused journey). **The 29 idle ships locked under v173 now accept updates: N-01 is fixed in production.** 30 ships with history keep identity protection (Q4). The paused journey's `arrival_at_unix` is `nil`. (`readonly_policy_and_admin_check.txt`) |
| Admin overview on real data | rendered for 15 real users with membership records, **0 errors** (same READ ONLY transaction) |
| Note | The audit's `ships_status_locked_while_idle` (29) still uses the pre-M03 definition, "has receipts and no unfinished journey". Under the new policy those ships are *not* locked, as the live policy check above shows. Renaming this audit key is a cosmetic follow-up. |

## Monitoring (≥ 30 min after maintenance off)

Monitoring started at maintenance-off (05:12:13 UTC). One background sampler took 6 samples, then one closing sample was taken. No duplicate monitor was started. Raw rows: `monitoring_samples.txt`, `closing_sample.txt`.

| Sample (UTC) | Tick | Tick failures | Last-tick age (s) | Failed jobs | Unfinished | Dup. unfinished | Pending arrival events | Router 5xx | `/api/status` responses | Release error markers |
|---|---|---|---|---|---|---|---|---|---|---|
| 05:18:50 | 811577 | 0 | 11 | 0 | 1 | 0 | 4 (prod) | 0 | none in window | 0 |
| 05:23:22 | 811589 | 0 | 70 | 0 | 1 | 0 | 4 | 0 | none | 0 |
| 05:27:52 | 811601 | 0 | 55 | 0 | 1 | 0 | 4 | 0 | none | 0 |
| 05:32:25 | 811612 | 0 | 38 | 0 | 1 | 0 | 4 | 0 | none | 0 |
| 05:36:57 | 811624 | 0 | 22 | 0 | 1 | 0 | 4 | 0 | none | 0 |
| 05:41:27 | 811636 | 0 | 6 | 0 | 1 | 0 | 4 | 0 | none | 0 |
| **14:38:25 (closing)** | 812978 | 0 | 3 | 0 | 1 | 0 | 4 (prod) | 0 (77×200, 2×304) | none | 0 |

Observed duration: **9 h 26 min** (05:12:13 → 14:38:25), well past the 30-minute minimum. The sampler's own window ended at 29 min 14 s; the closing sample completes the requirement without restarting the timer.

**Tick processing after recovery.** 05:18:50 → 05:41:27: 59 ticks in 1,357 s (23.0 s/tick). 05:41:27 → 14:37:45: 1,339 ticks in 32,178 s (**24.0 s/tick**). The pre-release preflight window ran at a similar ~24–26 s/tick. Configured `seconds_per_tick` is 15; the self-chaining `TickJob` waits 15 s after each completion, plus delayed_job polling. So **the cadence is unchanged by the release**. `failure_count` 0 throughout; `last_recovered_at`, `last_tick_failed_at` and `last_tick_error_class` all **never/none**, so the watchdog never had to intervene. The single 70 s age reading (05:23:22) is one slower tick inside an interval that still completed its normal 12 ticks. It is not a stall.

| Check (playbook / closure brief) | Result |
|---|---|
| 1 Intended release | v179 "Deploy 3d7e1dc2" current at 14:38 UTC |
| 2 Web and worker | web.1 up since 05:11:23, worker.1 up since 05:12:18; no R/H dyno errors in logs |
| 3 Tick cadence | stable, see above |
| 4 Failed background jobs | 0 throughout |
| 5 DB integrity | no duplicate unfinished journeys; casefold shard duplicates 0; row counts unchanged (shards 6, users 124, shard_users 155, user_ships 229); latest migration `20261116020000` |
| 6 `/api/status` errors | none: no `/api/status` requests at all in any sampled window (see "Unverified behavior") |
| 7 Location regressions | no location writes since release (`location_source` set on 0 rows; 0 `shard_users`/`user_ships` rows written); no `status_location_ignored`, `gate_request_failed` or `lazy_arrival_failed` markers |
| 8 Interdicted journeys | the single unfinished journey is still paused with `arrival_tick = 0`; **row not modified since release** (last updated 2026-11-13) |
| 9 RabbitMQ | unchanged pre-existing outage (4 prod events pending before and after; 0 new prod events created; 0 events sent since release) |
| 10 Migration, app and authorization errors | none (`NoMethodError`, `ActionView::Template::Error`, R/H errors all 0) |

**Rollback thresholds: none reached.**

## Decisions recorded for this milestone

| ID | Decision |
|---|---|
| R1 | GO: deploy RC `3d7e1dc` as v179 with the maintenance sequence; no staging app exists, so qualification is the green merged suite, migration rehearsals and race tests |
| R2 | Backup verification by capture plus Heroku Completed status (no download of production data) |
| R3 | Production smoke is read-only only (no test identity, no status/Jump writes) |
| R4 | Proceed despite the pre-existing prod broker outage; treat prod `arrival_delivery_failed` as a baseline, not a rollback trigger; owner follow-up |

## Rollback status

Not triggered. If needed: `heroku rollback v178 -a star-trader`. v178's code tolerates the added nullable columns, the unique index and the widened cargo precision. Do not run reverse migrations during an incident.
