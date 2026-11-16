# M07 — Cross-cutting integration and live-data safety review

**Verdict: PASS (2026-11-16).** There are no unexplained regressions, every approved decision traces to code and tests, and the migrations are rehearsed. Live data needs **no automatic repair** and none is proposed.

## Acceptance matrix (playbook M07)

| Area | Evidence |
|---|---|
| Status | Good, blank and unresolved location: M04 tests plus R-3. Username collision: R-5 and the F-05 tests. New and existing identities: existing status suite. Case-variant shard: R-4 and `status_reliability_test`. Reassignment refused for ships with history, audited for ships without: `status_location_sync_test`, `trades_controller_test`. Legacy payload: F-19 tests. HTTP 200 during active and paused travel: R-2, existing in-transit tests, `unix_time_contract_test`. |
| Jump | Real gateway only (Q2): `gate_travel_controller_test` refusal test. Player and ship at origin and arrival: R-1, `location_sync_test`, lifecycle tests. One journey on retry: receipt replay tests. Missing `ShardUser`: F-15 test. Interdicted and resumed: lifecycle and resume suites. Rabbit environment: `gate_routing_test`. |
| Concurrency | **New:** status racing a Jump departure (one journey; ship and player aligned at the gateway). Existing: status vs arrival, status vs pause, a different ship vs a shared player, two Jump starts, ordinary vs gate start, repeated arrival (all PostgreSQL multi-connection races) |
| Admin | 3 memberships × 8 ships, real wallets, divergence and stale labels, interdiction sentinel, query count independent of N, authorization, no UID to third parties (M01). Instrumentation (M03), time zones (M05), and **new:** a multi-ship explanation, see below. |
| Time | Integer or `null` `_at_unix` values; ticks unchanged; no epoch-zero for interdiction; explicit zone; DST; stall behavior; orbital and travel-timing suites unchanged (M05) |
| Data | Historical JSON strings and objects readable; coordinate keys preserved; casefold shard audit 0; no backfills |
| Integration | Status contract additive except Q3 (unknown shard → 404); Jump contract additive except Q2 (off-gateway → 422); the positional Rabbit event is unchanged (M05 test); no real broker in any test (`no_real_broker` support); CORS untouched |

## Live data: read-only reconciliation sizing (decision P2, counts only)

`heroku pg:psql -a star-trader -f docs/evidence/status-location-time/M07/prod_reconciliation_readonly.sql`, run in a `READ ONLY` transaction (`read_only = on`) and closed with `ROLLBACK`. Output is in `prod_reconciliation_output.txt`.

| Measure | Value |
|---|---|
| Diverged idle ship/player pairs | **64** (61 on ships that never travelled since v172, 3 on ships with receipts) |
| …of which belong to players with more than one ship | **64 / 64** (36 players) |
| Players with more than one ship | 41 |
| Unfinished journeys | 1 (paused, `arrival_tick = 0`; the protected 5071) |

**Conclusion.** Every diverged pair belongs to a multi-ship player. A player can be beside only one of their ships, so a parked ship elsewhere is the normal state of such an account, not corruption. **No reconciliation is proposed or warranted.** The release does nothing to these rows: idle pairs converge on the player's next applied status report or completed journey. The admin page now explains this beside the comparison table (`data-multi-ship-note`).

A record-level list (numeric IDs) was attempted and **blocked by the session's permission policy**, because decision P2 approved counts only. It was not retried or worked around. If the owner wants per-record review, the rebuilt admin user page shows the same information per player after release. Alternatively, explicitly authorize an ID-level read-only export.

## Static and migration checks

| Check | Result |
|---|---|
| `rails zeitwerk:check` | "All is good" |
| `rails db:rollback STEP=2` then `rails db:migrate` (both new migrations, isolated test DB) | reverted (index dropped, columns removed), re-applied; `db/schema.rb` round-trip **byte-identical** |
| `git diff --check c73b582` | only `\r` endings on added lines inside a file region that is CRLF; consistent with the file, not new whitespace |
| Secret scan of the full task diff | no credentials; only prose mentioning the earlier `fe_sendauth` blocker |

## Tests actually run

| Command | Result |
|---|---|
| `bin/codex_test test/services/status_location_sync_concurrency_test.rb` | 5 runs, 38 assertions, 0 failures (new departure race included) |
| `bin/codex_test` (full) | **658 runs, 6758 assertions, 33 failures, 24 errors**. **0 new** against the 58-identity M00 baseline; 1 fixed (M04). |

## Carried into M08

* The P0 merge of `origin/main` (`4f42a56`), which brings `61331ac` (`JsonStoreCoder`, menu/contact fixes, regression test repairs) and migration `20261024170000_widen_cargo_unit_prices` (**not yet applied in production**). Two expected test reconciliations are listed in `M04/RESULT.md`.
* G3/G4: there is no StarTrader staging app on the Heroku account (verified with `heroku apps`), so nonproduction qualification needs an owner go/no-go on the alternative evidence. The newest backup, `b005` (2026-11-01), predates v173–v178, so a fresh capture plus a restorability check is required before migrating.
