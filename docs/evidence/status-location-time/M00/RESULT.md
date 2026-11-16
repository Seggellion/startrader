# M00 — Revalidate checkout, decisions, tests, and deployment authority

**Verdict: PASS (gate G0 met), 2026-11-16.** M00 started BLOCKED: there was no authorized test database, and the integration base was undecided. The owner then answered P0, P1, P2 and Q1 (see `DECISIONS.md`). After that, the isolated baseline ran, all seven reproductions produced observed results, and the read-only production audit ran. Q2, Q3, Q4 and Q6 are still pending. They gate M02 and M04, not M01. No feature code was edited in M00.

Recorded: 2026-11-16 (UTC), Claude Code session.
Inputs: `docs/STARTRADER_STATUS_LOCATION_TIME_DISCOVERY.md` (sha256 `043742d4bfff8e5f…`, 15 Nov 2026) and `docs/STARTRADER_STATUS_LOCATION_TIME_REPAIR_PLAYBOOK.md` (sha256 `1e8f0aec0e049d33…`). The playbook was copied unchanged from the uploaded, untracked file in the main checkout. The original stays in place.
`AGENTS.md`: **does not exist** in this repository or the main checkout. `README.md`'s "Local Codex Verification" section is the governing test procedure (`bin/codex_db_doctor`, `bin/codex_test`).

## 1. Material deviation: the discovery baseline is stale

The discovery inspected `4f42a56`, the GitHub `main` tip. **Production does not run that line.**

| Ref | SHA | Verified how |
|---|---|---|
| GitHub `origin/main` | `4f42a566b73f…` | `git ls-remote origin refs/heads/main` (live) |
| GitHub `production-v178` | `c73b582fd76d…` | `git ls-remote origin` (live) |
| Heroku `star-trader` `main` | `c73b582fd76d…` | `git ls-remote heroku refs/heads/main` (live) |
| Heroku current release | **v178 "Deploy c73b582f"**, 2026-11-06 07:54 −07:00 | `heroku releases -a star-trader` (read-only) |
| Local `main` | `fecb49f` (34 behind `origin/main`) | `git branch -vv` |

* Merge base of `4f42a56` and `c73b582`: `9bc1d17`. Neither line contains the other.
* `c73b582` has **24 commits** that `4f42a56` lacks. They include releases v172–v178, which changed the code paths in this project's scope: `b824721` (jump travel lifecycle and durable arrival delivery), `ccf02b2` (status location sync, v173), `26a17ff` (admin interdiction resume), `4d9d70a` (repeat-jump guard), `eacc1e7` (gate broker routing), `cb27631` (bare jump restore, v177), plus four new migrations `20261101010000`–`20261101010300` and `20261104010000`.
* `4f42a56` has **15 commits** that production lacks. Most are terminal-filter commits that also exist on the production line under different SHAs. Unique code: `61331ac` (the `JsonStoreCoder` change, menu/contact fixes, and migration `20261024170000_widen_cargo_unit_prices`) and `5576bb0`.
* Unreleased branches already sit **on top of v178**: `claude/interdiction-hold-release-prod` (+3, interdiction hold recovery) and `claude/interdict-endpoint-containment` (+1, worktree `startrader-interdict-login-d01ee6`). Neither is deployed (Heroku `main` = `c73b582`).
* The main checkout's branch `codex/restore-bare-jump` (`6326f24`) is `cb27631` plus two documentation commits. It is not an ancestor of `c73b582`.

**Consequence:** deploying anything built on `4f42a56` would roll back v172–v178. The repair must be built on the production line, and M08/M09 must reconcile GitHub `main` with production. See decision P0 in `DECISIONS.md`.

## 2. Discovery findings revalidated against production source `c73b582`

Static revalidation by source reading. No tests were run (see §4).

| ID | State at `c73b582` | Evidence |
|---|---|---|
| F-01 Jump departure player write | **Fixed (v172)** | `GateTravelService#create_gate_travel!` now calls `user_ship.shard_user&.update_current_location!(origin_location)` in the travel transaction. The arrival guard is still equality-based, but its precondition now holds at departure. |
| F-02 Jump teleport to a named remote gateway | **Present, by earlier owner-accepted design.** Player now moves with the ship (aligned teleport). | `resolved_origin_gateway` still returns any named gateway in the current system. `docs/discovery/jump_intent_release_20261105.json`: *"First blank jumps and remote named gateway selection remain supported."* |
| F-03 Status overwriting in-flight location | **Fixed, then over-corrected (see N-01)** | `StatusLocationSync` ignores client location for "managed" ships/players and returns `location_sync.status=ignored, code=stale_location`. |
| **N-01 (new) Status permanently ignores location after any travel** | **Present — probable root cause of objective 1** | `StatusLocationSync.travel_exists?` is true if *any* `ShipTravel` **or any `TravelRequestReceipt`** exists. Receipts never expire (`travel_request_receipt.rb`: *"No expiry in this release"*). So `player_location`/`ship_location` are `nil` forever for every ship that has travelled since v172, and for every player owning such a ship. v173's own evidence states the limitation: *"Such locations are preserved and require actual server travel or a separately designed explicit reconciliation mechanism."* |
| N-02 (new, probable) Status aborts on a managed ship whose `ship_model` string differs | Present | `trade_service.rb`: raises `status_identity_conflict` when a managed ship's `[user, shard, shard_user, ship]` differs. `find_or_create_status_ship!` creates a *new* `Ship` for an unmatched model string before the check. |
| F-04 Shard create-on-miss, case-sensitive | Present | `find_or_create_status_shard!` unchanged |
| F-05 Username collision aborts | Present | unconditional `user.update!(attrs)`. v173's evidence lists `test_status_treats_same_player_name_with_different_player_guid_as_different_user` as a **baseline failure**. |
| F-06 Status reparenting | **Partly fixed** — refused for managed ships, still allowed for ships with no travel history | `status_identity_conflict` guard |
| F-09 Admin user view lacks `ShardUser` | Present | `show.html.erb` gained only a `TravelState` label |
| F-10 / F-11 / F-23 | Present | `Api::TickController < ApplicationController`; `resources :users`; `byebug` at `moves_controller.rb:7` |
| F-12 15 000 grant | Present (out of scope; Q7) | `trade_service.rb:533` |
| F-13 Paused `ship.time_remaining` | Present | `trade_service.rb:410` still `seconds_remaining` |
| F-15 `ShipAvailability` nil `shard_user` | **Fixed** | `return unless shard_user` |
| F-17 Unbounded `retry` | Present | `trade_service.rb:95`, `star_trader_ship_sync.rb:51` |
| F-18 Unresolvable location → 400 | Present | `trade_service.rb:241` |
| F-19 Path predicate mismatch | Present | `trades_controller.rb:251` |
| F-20 `deliver_ship` bypass | Not re-examined in detail; presumed present | — |
| F-22 Jump broker routing | **Fixed (v176)** | `GateTravelRouting` — explicit request → receipt → shard default → global default |
| Jump idempotency / concurrency | **Largely fixed (v172)** | durable receipts, GUID advisory locks, `TravelLifecycle.assert_free!`, unique unfinished-journey-per-ship index (`20261101010200`) |

## 3. Release topology (no credentials recorded)

* **Production authority: verified.** Heroku app `star-trader`, region `us`, stack `heroku-24`, add-on `heroku-postgresql:essential-0`, formation `web: 1, worker: 1`. Git URL `https://git.heroku.com/star-trader.git` (= `heroku` remote).
* **Deployment pathway:** Heroku Git push. Every release from v173 to v178 is described as "Deploy <sha>" by the owner's account. No GitHub-to-Heroku auto-deploy was observed in the release descriptions; this still needs confirming in M08.
* **GitHub:** `Seggellion/startrader`, `main` **not protected** (`gh api …/branches/main/protection` → 404). PRs have been the historical merge route (#24–#38).
* **Main checkout** (`/home/dusti/startrader`): on `codex/restore-bare-jump` (not `main`). **Dirty**: modified `config/initializers/cors.rb`, plus many untracked user files (uploaded playbooks, CORS discovery/resolution docs, `docs/discovery/*`, `test/controllers/api/catalog_cors_test.rb`). None of these may be touched. M09 cannot "merge into the main checkout" until the owner decides how (P0).
* **Worktrees (all preserved):** `/home/dusti/startrader` (main checkout), `.claude/worktrees/friendly-leakey-963229`, `.claude/worktrees/startrader-interdict-login-d01ee6`, `tmp/maidenbot-cors-20261106/release-worktree`, and this one.
* **Task-owned worktree for M10 removal:** `/home/dusti/startrader/.claude/worktrees/startrader-discovery-fa1f6d`. This worktree was created for this Claude session. In M00 it was switched, non-destructively, from `claude/startrader-discovery-fa1f6d` (`4f42a56`, no unique commits) to the new task branch **`claude/status-location-time-repair`**, based on `c73b582` (production v178). Branch `claude/startrader-discovery-fa1f6d` keeps no unique work.
* **Backups/rollback:** not verified yet (M08). History shows a backup `b005` and an ActiveRecord-only migration runner were used for v172.

## 4. Tests

Profile: `.env.terminal-test` (decision P1). It is referenced through `CODEX_ENV_FILE=/home/dusti/startrader/.env.terminal-test` and was never copied. Loopback PostgreSQL `star_trader_terminal_test`, `PARALLEL_WORKERS=1`, `TICK_BOOTSTRAP=false`. Raw logs are kept locally in the ignored `tmp/slt/`.

| Command | Result |
|---|---|
| `bin/codex_db_doctor` (no profile) | `fe_sendauth: no password supplied` (the original blocker) |
| `bin/codex_db_doctor --require-connection` (with profile) | connected as the limited test role; "Codex database access works" |
| `bin/codex_test` (full suite, `c73b582`) | **621 runs, 6484 assertions, 33 failures, 25 errors, 0 skips** |
| `bin/codex_test docs/evidence/status-location-time/M00/repro_test.rb` | **7 runs, 19 assertions, 5 failures, 0 errors** — all five failures were predicted |

**Baseline classification.** The 58 failing identities (written to `tmp/slt/m00_baseline_identities.txt`) **match exactly** the 58 identities recorded in `docs/discovery/jump_travel_repair_regressions.json`. That is 0 new and 0 missing. By class: Admin::Data 9, Menus 6, Api::Commodities 6, TradeService 5, MenuItems 5, Api::Trades 5, Admin::Terminals 5, Admin::Commodities 4, Admin::ProductionFacilities 3, Admin::Outposts 2, Admin::ContactMessages 2, Admin::Cities 2, TickRunner 1, ShardUser 1, MarketPriceUpdater 1, Admin::Dashboard 1. Many of these are the failures that GitHub `main`'s `61331ac` ("Repair full regression suite…") fixed on the other line, so the M08 merge of `origin/main` should shrink this set. G2 for every milestone is **"no new identities versus this 58-identity baseline"** until that merge. Note: `bin/codex_test` labels this run `[Rails database preparation failure]` because test output contains `ActiveRecord::`. That label is a classifier artefact. `db:prepare` succeeded.

**Pre-fix reproductions (observed).**

| Test | Predicted | Observed |
|---|---|---|
| R-1 / F-01 Jump aligns player at departure and arrival | PASS (fixed v172) | **PASS** |
| R-2 / F-03 in-flight conflicting status location ignored, journey untouched | PASS (fixed v173) | **PASS** |
| R-3 / F-18 unresolvable location degrades | FAIL | **FAIL** — `400 {"message":"Location not found: Not A Real Place"}`, wallet not applied |
| R-4 / F-04 case-variant `shard_uuid` | FAIL | **FAIL** — `Shard.count` +1 (expected 0 difference) |
| R-5 / F-05 username collision | FAIL | **FAIL** — `422 "Validation failed: Username has already been taken"` |
| R-6 / F-13 paused countdown consistency | FAIL | **FAIL** — `travel.time_remaining` 50, `ship.time_remaining` 0 |
| N-01 idle status after a completed journey | FAIL | **FAIL** — location stayed `"Repro Here"` (expected `"Repro There"`) |

## 5. Production read-only evidence (decision P2)

`heroku pg:psql -a star-trader -f docs/evidence/status-location-time/M00/prod_readonly_audit.sql`. Run inside `BEGIN TRANSACTION READ ONLY` with a 20 s statement timeout and closed with `ROLLBACK`. The output confirmed `transaction_read_only = on`. Aggregate counts only, saved as `M00/prod_readonly_audit_output.txt`.

| Probe | Result | Conclusion |
|---|---|---|
| `last_location` storage | 154 `string` (double-encoded), 1 SQL NULL, **0 native objects** | F-07 confirmed in production. P-03 (mixed representation) **refuted**: every row is a string. |
| Payload shape | 154 have a name, **0 have any `x/y/z` key** | P-02 **refuted**: no legacy coordinates exist in production |
| Case/whitespace-variant `channel_uuid` groups | **0** (6 shards, 1 with the auto-created `Shard …` name pattern) | P-04 **refuted** for now. F-04 is latent, not yet fired. A unique index is currently safe. |
| Ship location missing from the catalog | 0 of 229; 0 ships without `shard_user` | U-04 clean |
| **Ship vs player divergence** | idle: **64 of 228 pairs diverged** (163 aligned, 1 player unknown); in flight: 1 of 1 diverged | P-05 **confirmed**. 28% of idle ships disagree with their player. |
| **N-01 impact** | 30 ships have receipts; **29 idle ships (28 players) are permanently status-locked** | N-01 **confirmed** as live impact. Receipt outcomes: 155 completed, 4 cancelled, 1 pending. |
| Unfinished journeys | 1 (paused, `arrival_tick = 0` sentinel, not gate) | consistent with the protected 5071 record |
| Duplicate `twitch_id` groups | 0 (124 users) | §9.3 risk not realized |
| Migrations | `20261101010000…0300` and `20261104010000` present; **`20261024170000` (widen cargo prices, from GitHub `main`) absent** | the M08 merge of `main` brings in one pending migration. It must be reviewed as part of the release. |

Production logs (`heroku logs -n 1500`) covered only a 19-minute window with no status traffic. **Inconclusive** for the 400/422 rate. The sample was deleted after counting.

## 6. External client contract (Q6 evidence gathered)

* The live bot's Jump requests contain **only `ship_guid` + auth — no gateway, no preconditions, no `travel_guid`** (`docs/discovery/bare_jump_release_20261105.json`). v175 broke this; v177 restored it after "nobody can travel". **Requiring `travel_guid` is confirmed client-breaking. Do not do it** (this supersedes playbook M02 step 4).
* External bot source is unavailable (every 5 Nov release record says so). No evidence yet on its use of `ship.time_remaining`, of status response keys, or of the v173 `location_sync` key.

## 7. Gate G0 checklist

| Requirement | State |
|---|---|
| Correct repository and all worktrees identified | ✅ |
| Working state preserved | ✅ No user file touched. The only writes are this worktree's branch switch and new docs/evidence files. |
| Isolated `bin/codex_test` baseline accessible | ✅ 621 runs. 58 known identities, 0 new. |
| Recovery and production topology established | ✅ Production identity verified; integration base decided (P0). Backup/restore verification is assigned to M08/G3. |

## 8. Next gate

**M00 PASS → M01 may start.** M01 is the read-only admin rebuild plus an audit task. It depends on no pending decision.
Pending decisions and what they block: **Q2** → M02 gateway rejection. **Q3, Q4** → M04. **Q6** → the M02/M05 compatibility of changed keys. Never require `travel_guid`.
Scope note for M03/M04, from Q1 and N-01: narrow `StatusLocationSync` so that only an *unfinished* journey makes a ship/player "managed". Completed and cancelled receipts must no longer block idle status sync. This is the most direct fix for objective 1, and it affects 29 production ships.

Rollback for M00: no application, schema or data changes. To undo, return this worktree to its former branch: `git switch claude/startrader-discovery-fa1f6d`.
