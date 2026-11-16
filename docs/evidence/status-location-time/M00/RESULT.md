# M00 — Revalidate checkout, decisions, tests, and deployment authority

**Verdict: BLOCKED (gate G0 not met).** Two reasons: no authorized isolated test database is available, and the integration base needs an owner decision because GitHub `main` and production are on divergent lines. Under the playbook's M00 rule, no feature code has been edited.

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

**Tests actually run: none.**

| Command | Result |
|---|---|
| `bin/codex_db_doctor` | `pg_isready`: accepting on `/var/run/postgresql:5432`. `psql -w -d star_trader_test` → **`fe_sendauth: no password supplied`**. No `.env.codex` exists in this worktree. |
| `bin/codex_test` | Not run (database not preparable) |
| R-1 … R-6 | Not run. They remain **predictions** — and are now partly obsolete: R-1's departure half should pass at `c73b582` (F-01 fixed), and R-2 should pass (F-03 fixed). R-3 (F-18), R-4 (F-04), R-5 (F-05) and R-6 (F-13) are still predicted to fail. A new reproduction is required for N-01 (status location after a completed journey). |

Credentials found in other local `.env.*` profiles were **not** used, per the kickoff instruction. Earlier projects ran on `.env.terminal-test` (PostgreSQL 18 loopback, `star_trader_terminal_test`) and on a disposable PostgreSQL 16 cluster (`docs/STARTRADER_JUMP_TRAVEL_REPAIR_STATUS.md`). Reusing either needs explicit owner authorization (decision P1).

Historical baseline for comparison: v173 recorded the status group at *64 tests, 2 failures, 1 error*. The jump-repair M6 full-suite candidate recorded *523 runs, 33 failures / 25 errors, matching 58 fresh baseline identities*. **The full suite is not green on the production line**, so G2 has to compare against a fresh baseline, not expect zero.

## 5. Production read-only evidence (P-01…P-05)

* `heroku logs -n 1500 -a star-trader` (read-only): the buffer covered only 2026-11-16 01:11–01:30Z. It contained **zero `/api/status` requests**, and zero `location_update failed`, `status_location_ignored` or `status_identity_conflict` markers. **Inconclusive.** No log drain with history appears to exist. The scratch copy was deleted immediately and only counts were kept.
* No production database query was run. The read-only audit (`jsonb_typeof`, case-folded `channel_uuid` duplicates, divergence) needs explicit authorization (decision P2). An existing reviewed tool is available: `docs/discovery/read_only_travel_audit.rb`.

## 6. External client contract (Q6 evidence gathered)

* The live bot's Jump requests contain **only `ship_guid` + auth — no gateway, no preconditions, no `travel_guid`** (`docs/discovery/bare_jump_release_20261105.json`). v175 broke this; v177 restored it after "nobody can travel". **Requiring `travel_guid` is confirmed client-breaking. Do not do it** (this supersedes playbook M02 step 4).
* External bot source is unavailable (every 5 Nov release record says so). No evidence yet on its use of `ship.time_remaining`, of status response keys, or of the v173 `location_sync` key.

## 7. Gate G0 checklist

| Requirement | State |
|---|---|
| Correct repository and all worktrees identified | ✅ |
| Working state preserved | ✅ No user file touched. The only writes are this worktree's branch switch and new docs/evidence files. |
| Isolated `bin/codex_test` baseline accessible | ❌ **BLOCKED — P1** |
| Recovery and production topology established | ⚠️ Production identity verified; integration base needs a decision (**P0**); backup not yet verified (M08) |

## 8. Next gate

M00 → PASS requires: **P0** (integration base) and **P1** (test-database profile) answered, then a green-or-classified `bin/codex_test` baseline on `claude/status-location-time-repair`, plus observed results for the revised reproductions (R-3…R-6, N-01). M01 (admin view, read-only) can start immediately after that. It does not depend on Q1–Q4.

Rollback for M00: no application, schema or data changes. To undo, return this worktree to its former branch: `git switch claude/startrader-discovery-fa1f6d`.
