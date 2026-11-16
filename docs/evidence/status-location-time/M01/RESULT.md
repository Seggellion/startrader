# M01 — Admin user view and read-only integrity instrumentation

**Verdict: PASS (2026-11-16).** No schema change, no data write, no change to any write path. Discovery findings resolved: **F-09** and **F-21** (for the user page), plus the admin half of the crafatar leak. Read-only instrumentation now exists for P-02 through P-05 and N-01.

Baseline: task branch `claude/status-location-time-repair`, based on `c73b582` (production v178).

## Changed files

| File | Change |
|---|---|
| `app/services/admin/user_overview.rb` (new) | Read-only presenter. Loads the user, memberships, shards, ships, cargo, commodities, unfinished journeys and their locations, catalog names, tick, seconds-per-tick, tick control and shard-UUID variant groups in a fixed number of queries. Classifies each ship/player pair as Aligned, Diverged, Unknown, In transit or Interdicted. Decodes every JSON store safely: a bare-string row raises `JSON::ParserError` in the model coder, and on this line `coder: JSON` raises `TypeError` for native jsonb objects. The presenter falls back to decoding the raw column. |
| `app/helpers/admin/users_helper.rb` (new) | Explicit `… UTC` timestamps with labelled missing values, comparison and status badges, local initials avatar, aUEC formatting, safe pretty JSON |
| `app/views/admin/users/show.html.erb` (rewritten), `_membership.html.erb`, `_ship.html.erb` (new) | Light-modern tokens from `admin/user_ships/edit` (D3). Contents: status ribbon (tick, memberships, ships, in transit, interdicted, location mismatches); identity panel; one panel per `ShardUser` with real per-shard wallet, stats, named location, star system, classification, catalog resolution or a stale badge, legacy `x/y/z` only when present, a player-vs-ship comparison table, and raw stored payload with its storage form; per-ship location, cargo and journey (state label, ticks, interdicted sentinel label, remaining ticks, broker); "No journey on record"; unlinked ships section; collapsed tick-chain diagnostics; and an explicit "not yet instrumented" note |
| `app/controllers/admin/users_controller.rb` | `show` builds `Admin::UserOverview` with `Cache-Control: no-store`. The existing admin login and role filters are unchanged. |
| `app/views/admin/users/index.html.erb` | crafatar fallback replaced by local initials (no third-party request keyed by UID) |
| `app/views/admin/shared/_side_bar.html.erb` | added a ShardUsers link (one line; CRLF endings preserved) |
| `app/services/status_location_audit.rb` (new), `lib/tasks/status_location.rake` (new) | `bin/rails status_location:audit` reports aggregate counts only, inside a PostgreSQL `READ ONLY` transaction that ends in rollback. Payloads are decoded in Ruby (F-07). |
| `test/controllers/admin/user_overview_test.rb` (new, 6 tests), `test/services/status_location_audit_test.rb` (new, 2 tests) | see below |

## Tests actually run

Profile: `CODEX_ENV_FILE=/home/dusti/startrader/.env.terminal-test` (decision P1).

| Command | Result |
|---|---|
| `bin/codex_test test/controllers/admin/user_overview_test.rb test/services/status_location_audit_test.rb test/controllers/admin/travel_diagnostics_test.rb` | **12 runs, 155 assertions, 0 failures, 0 errors** (includes the pre-existing v172 travel diagnostics test, which asserts `Interdicted` on `/admin/users/:id`) |
| `bin/codex_test` (full) | **629 runs, 6590 assertions, 33 failures, 25 errors**. The 58 failure identities are **identical to the M00 baseline: 0 new, 0 fixed.** (One apparent difference was the M00 extraction truncating a test name at `-`. The canonical identity list is now `tmp/slt/baseline_identities_canonical.txt`.) +8 runs = the new tests. |
| `bin/rails status_location:audit` (isolated test DB) | ran; `transaction_read_only: "on"` |

Coverage against the playbook's M01 verification list:
* Multi-shard and multi-ship (3 memberships × 8 ships): every panel and ship renders, with the real per-shard wallet and its shard UUID.
* All five comparison states, and ribbon counts.
* Paused `arrival_tick = 0` shows "(interdicted sentinel, not an arrival deadline)" and "No scheduled arrival while interdicted".
* "No journey on record" and explicit UTC labels.
* Historical `last_location` shapes `{}`, bare string, array, SQL NULL and native object all render. Coordinates appear only for the row that has them.
* Stale catalog names (player and ship); a ship with no membership; a user with no memberships.
* **The query count is identical** for 2 memberships × 5 ships and 3 × 8 (both with an active and an interdicted journey), and ≤ 30. Cached calls are counted, because the test connection keeps its query cache across requests.
* Anonymous visitors are redirected to login; players are redirected to root.
* No secret in the page, no crafatar, no `<img>` carrying the UID (show and index).
* The page performs no write: `id`/`updated_at` snapshots of six tables are unchanged.
* Audit counts are correct on synthetic data. Its output contains none of the planted usernames, UIDs, GUIDs, shard UUIDs or location names. It issues no INSERT, UPDATE, DELETE or DDL.

## Before-state metrics (to compare after deployment)

The new rake task cannot run in production until it is deployed. The before-state is the M00 SQL audit (`M00/prod_readonly_audit_output.txt`, release v178): idle pairs 163 aligned / **64 diverged** / 1 unknown; 1 interdicted pair; **29 idle ships (28 players) status-locked** by receipts; 0 legacy coordinates; 0 case-variant shard groups; 154/155 `last_location` stored as double-encoded strings.

## Findings recorded during M01

* **M01-a (latent, production line):** `ShardUser` on `c73b582` still uses `store … coder: JSON`, which raises `TypeError` when reading a native jsonb object. Production has 0 such rows (M00 audit A), so nothing breaks today. GitHub `main`'s `61331ac` (`JsonStoreCoder`) fixes it and arrives with the P0 merge in M08. The admin page does not depend on either coder.
* **M01-b (latent):** a `last_location` holding a bare JSON string such as `"Area18"` makes the coder raise `JSON::ParserError` on every model read, including `/api/status`. Production has 0 such rows. The admin page is resilient. The model fix is out of M01 scope and should be noted for M03 when location writes are consolidated.

## Not done / limits

* **No browser render.** Google Chrome is not installed in this WSL environment. Evidence is HTML assertions only. Visual qualification is deferred to M08's nonproduction rehearsal.
* `admin/users/index` keeps its dark styling (aligning it is optional; D3 covers only the show page).
* Diagnostics for *last location update* and *location source* depend on M03's additive columns.

## Rollback

Revert the M01 commit. It contains no schema or data change.
