# M03 — One location authority and atomic travel lifecycle

**Verdict: PASS (2026-11-16), engineering only.** The G3 production gate for the new migration (a restorable backup and a production schema check) is deferred to the M08/M09 release preflight, as the playbook requires. No production action was taken.

Decisions applied: **Q1** with the owner's refinement (only an unfinished journey blocks status location, plus a 40-tick stale-origin guard), and **Q4** (ships with travel history keep their identity).

## What changed

| Area | Change | Findings |
|---|---|---|
| `app/services/location_sync.rb` (new) | Single writer for named locations: `player!`, `ship!`, `both!` (one transaction). Sources are restricted to `client_status`, `travel_departure`, `travel_arrival`, `repair`, `delivery`, `admin`. | F-03, F-20, discovery §1.2 ("seven writers, no owner") |
| `db/migrate/20261116010000_add_location_instrumentation_to_shard_users.rb` (new), `db/schema.rb` | **Additive, nullable** `shard_users.location_updated_at` (datetime) and `location_source` (string). No backfill: NULL means "not recorded". The schema diff is exactly these two columns plus the version bump. | §5.4 E instrumentation |
| `app/models/shard_user.rb` | `update_current_location!(location, source: nil)` still merges the named payload and preserves other keys (including legacy `x/y/z`). It sets the two markers **only when the location actually changes**, and tolerates non-Hash historical payloads. | D1, M01-b (partly) |
| `app/services/status_location_sync.rb` | **Narrowed (fixes N-01).** "Managed" now means an *unfinished* journey or a *pending* receipt, not any receipt ever. A report naming the origin of a journey that completed within `STALE_ORIGIN_WINDOW_TICKS = 40` is ignored (`code: stale_location`, new `reason: recent_origin` / `in_flight`). New `travel_history?` keeps v173's identity protection. | N-01, F-03, Q1, Q4 |
| `app/services/trade_service.rb` | Status player/ship writes go through `LocationSync` (`client_status`). The identity guard uses `travel_history?`. | N-01, Q4 |
| `app/services/travel_service.rb`, `gate_travel_service.rb` | Departure writes ship and player through `LocationSync.both!` (`travel_departure`) inside the existing `TravelLifecycle.with_ship` transaction. The discovery's "three separate statements" concern was already fixed in v172; the transaction is unchanged. | F-01 (atomicity) |
| `app/services/ship_travel_arrival_processor.rb` | Arrival lands **the ship and its own player together** (`travel_arrival`). The previous "player still equals origin" condition is removed. It is safe now: departure normalizes the player, and status cannot move a player whose ship is in flight. The arrival lock, idempotency, completion receipt and outbox event are unchanged. | F-01 (arrival), §9.5 soft-lock |
| `app/services/ship_availability.rb`, `app/controllers/api/ship_travel_controller.rb` | Repair and initialization writes go through `LocationSync` (`repair`) | — |
| `app/controllers/api/ships_controller.rb` | `deliver_ship` runs under `TravelLifecycle.with_ship`, is **refused while a journey is unfinished**, writes through `LocationSync` (`delivery`) and does not move the player | F-20 |
| Admin user page | Each membership shows "Location last changed … by <source>", or "Not recorded" | §5.4 E |

`grep -rn update_current_location! app` now finds exactly one caller: `LocationSync`.

## Intentionally revised tests (policy changes, not deletions)

| Test | Old assertion | New assertion | Why |
|---|---|---|---|
| `StatusLocationSyncTest` "completed receipt protection does not expire" | permanent protection | renamed "stale-origin guard ignores receipt age but expires after the tick window": ignored within 40 ticks, applied after | Q1 / N-01 |
| new: "idle status after a completed journey updates locations again (N-01)" | — | location applied, `location_source = client_status` | N-01 |
| "stale status cannot undo a completed gate arrival…", "matching report…", "legacy status cannot undo…", "location free status…", `Api::StatusLocationSyncTest` "flat and nested…" | whole-record byte equality | equality of location, identity and wallet fields (`location_state`), plus `reason: recent_origin` | Since Q1 an idle status may legitimately sync ship metadata (touch, shard name). The protected fields are unchanged. |
| "new ship initialization cannot bypass the saved player location", two concurrency tests | stale report named the start station | stale report names the jump's actual origin (the gateway) | Under Q2 the fixture walks to the gate, so the station is no longer a journey origin |
| `TravelRepairLifecycleTest` "arrival preserves player legitimately elsewhere" | player left behind at arrival | renamed "arrival lands the ship player even when diverged during flight" | M03 arrival rule |

New: `test/services/location_sync_test.rb` (6 tests). Covers: markers set only on change; legacy keys preserved; unknown source refused; ship and player roll back together; co-located departure is a no-op while arrival records `travel_arrival`; delivery refused during an unfinished journey and never moves the player.

## Tests actually run

| Command | Result |
|---|---|
| 20 travel/status/admin files (`m03_focus.log`) | **338 runs, 2637 assertions, 6 failures, 5 errors**. All 11 are baseline identities; 0 new. |
| `bin/codex_test test/services/location_sync_test.rb` | 6 runs, 24 assertions, 0 failures |
| `bin/codex_test test/controllers/admin/user_overview_test.rb` | 6 runs, 84 assertions, 0 failures |
| `rails db:rollback STEP=1` then `rails db:migrate` (isolated test DB) | reverted (columns removed), re-applied; `db/schema.rb` round-trip **byte-identical** |
| `bin/codex_test` (full) | **638 runs, 6641 assertions, 33 failures, 25 errors**. The same 58 baseline identities: **0 new, 0 fixed**. The canonical identity list was rebuilt with a broader name pattern; M01 and M02 recheck to 0 new / 0 fixed as well. |
| `bin/codex_test docs/evidence/status-location-time/M00/repro_test.rb` | 7 runs, 4 failures. **N-01 now passes**, and R-1 and R-2 still pass. The remaining R-3 (F-18), R-4 (F-04), R-5 (F-05) and R-6 (F-13) are M04/M05 scope. |

## Live-data impact to expect after release (from the M00 audit)

* **29 idle ships / 28 players** currently status-locked (N-01) will accept idle status location updates again. The exception is a report naming a journey origin that completed within the last 40 ticks.
* **64 diverged idle pairs**: nothing is moved automatically. Each converges on the player's next applied status report or completed journey. No backfill was made, and none is authorized.
* The single unfinished journey (the protected 5071, paused, `arrival_tick = 0`) is not touched. If it is ever resumed and arrives, the new arrival rule lands its player at the destination together with the ship, rather than leaving the player at HUR-L1. **Owner awareness item: 5071 remains paused; M03 performs no action on it.**

## Rollback

Revert the M03 commit to roll back the application. Keep the two nullable columns: older code ignores them, and dropping them during an incident is unnecessary. The `down` migration exists and was rehearsed.
