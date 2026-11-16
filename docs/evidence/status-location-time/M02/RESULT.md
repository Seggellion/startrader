# M02 — Jump synchronization and gateway integrity

**Verdict: PASS (2026-11-16).** Decision **Q2** has been implemented, and the remaining Jump gaps from the discovery are now covered by tests. Game time, travel duration, tick cadence, the broker message format, and interdiction rules are unchanged.

## Revalidated scope

Most of the discovery's M02 scope was already delivered in production v172–v176 (see M00 §2):

| Finding | State before M02 | M02 action |
|---|---|---|
| F-01 player not moved on Jump departure/arrival | fixed in v172 (`create_gate_travel!` normalizes the player in the travel transaction); R-1 passes | none; R-1 kept as evidence |
| **F-02 Jump to a remote named gateway relocates the ship** | present, deliberately kept by v175 | **fixed under Q2**: refused with `422 jump_not_at_gateway`, no side effects |
| **F-15 ship without `ShardUser`** | no longer crashed (v172 nil guard), but returned a misleading `location_mismatch` | **explicit `422 shard_membership_missing`, refused before any lock or write** |
| F-22 dev Jump published to the prod broker | fixed in v176 (`GateTravelRouting`); covered by `test/controllers/api/gate_routing_test.rb` | none |
| Idempotency and concurrency | fixed in v172 (durable receipts, GUID advisory lock, unique unfinished-journey index) | none. **`travel_guid` stays optional** (Q6: the live bot sends bare jumps). |

## Changed files

* `app/services/gate_travel_service.rb`:
  * `validate_at_origin_gateway!`. When `gateway_name` resolves to a gateway other than the ship's current location, the Jump raises `IntentError('jump_not_at_gateway')`. The error state carries `current_location`, `player_location`, `current_star_system` and `requested_gateway`. Because it is an `IntentError`, a due arrival already processed by the availability check still commits (the existing v175 contract), and nothing else changes.
  * A pre-lock check `shard_membership_missing`.
* `test/controllers/api/gate_travel_controller_test.rb`:
  * Four tests that asserted the relocation were **intentionally rewritten** to start at the named gateway. They keep their purpose of checking suffix-less, parenthetical and current-system name resolution. Rewritten: "can enter Nyx Gateway…", "can enter Stanton Gateway…", "full parenthetical…", "unqualified gateway lookup…".
  * New: "named gateway the ship is not at is refused without side effects (decision Q2, F-02)" and "jump by a ship with no shard membership returns a clear domain error… (F-15)".
  * Added the missing `require "minitest/mock"`. It is a pre-existing gap: the file failed when run alone.
* `test/support/travel_repair_fixtures.rb`: `gate_start` now walks ship and player from the start station to the gateway first (new `walk_to_gate!`), as a completed ordinary trip would. About 45 lifecycle and concurrency call sites keep their meaning.
* `test/services/travel_repair_lifecycle_test.rb`, two tests:
  * "preexisting mismatch rejects remote gateway…" now calls the service directly, so the deliberate player mismatch is not masked by the fixture walk.
  * "gateway ship save failure rolls back…" walks to the gate before capturing its baseline. Rollback is still asserted.
* `test/services/travel_repair_concurrency_test.rb`: in "simultaneous ordinary and gate starts…", both racing starts now depart from the gateway. Under Q2 they can no longer share the station. The invariant (exactly one wins, one journey, one receipt) is unchanged.

## Tests actually run

| Command | Result |
|---|---|
| 15 gate/travel/arrival/status-sync/resume files (`m02_gate.log`) | **143 runs, 1618 assertions, 0 failures, 0 errors** before the F-15 test was added |
| `bin/codex_test test/controllers/api/gate_travel_controller_test.rb` | **22 runs, 96 assertions, 0 failures** |
| `bin/codex_test` (full) | **631 runs, 6606 assertions, 33 failures, 25 errors**. The same 58 baseline identities: **0 new, 0 fixed**. +2 runs = the new tests. |

## Compatibility (Q6)

* The live bot sends `ship_guid` plus auth only, so its bare Jump never reaches `validate_at_origin_gateway!`. Its behavior is unchanged.
* A client that names a remote gateway now gets `422 {status:"error", code:"jump_not_at_gateway", message, current_location, requested_gateway, …}`. This is client-visible. Q2 approved it.
* No response key was removed or renamed.

## Rollback

Revert the M02 commit. There is no schema or data change, and no journey created before the change is affected.
