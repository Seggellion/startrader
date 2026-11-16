# M04 — Status reliability, identity and ship ownership

**Verdict: PASS (2026-11-16), engineering only.** The new unique index's production gate (a casefold duplicate re-check immediately before release, plus a restorable backup) is part of the M08/M09 preflight. The M00 audit found **0** case/whitespace-variant shard groups in production.

Decisions applied: **Q3** (refuse unknown shards, owner choice), **Q4** (reassign ships without travel history, but audited, owner choice), **Q6** (additive keys only). Findings resolved: **F-04, F-05, F-06 (per Q4), F-17, F-18, F-19**.

## Behavior changes

| Finding | Before | After |
|---|---|---|
| **F-18** unresolvable `location` | `400 "Location not found: …"`; nothing applied | **200**. Wallet, username and ship association are applied; saved locations are kept; `location_resolution: "unresolved"` plus a `location_unresolved` warning |
| **F-05** player name already held by another account | `422 "Username has already been taken"`; nothing applied | **200** with a `username_conflict` warning. An existing player keeps their current name. A *new* player is created as `<name>-<guid suffix>`. No account is taken over. |
| **F-04 / Q3** unknown `shard_uuid` | a new `Shard "Shard <uuid>"` was created silently, case-sensitive | **404 "Shard not found. Ask an administrator to register this shard."**. Matching is case/whitespace-insensitive everywhere: status (new and legacy), `/api/travel` (`StarTraderShipSync`), buy/sell (`find_trade_shard`). |
| F-04 duplicate prevention | none (`channel_uuid` unindexed) | `Shard` validation, plus migration `20261116020000` adding a unique index on `lower(btrim(channel_uuid))` where not null (built `CONCURRENTLY`) |
| **F-06 / Q4** reassigning an existing ship | silent for ships without history; refused for ships with history (v173) | still allowed for ships without history, but logged (`event=user_ship_reparented` with previous/new user and shard ids, no secrets) and reported as a `ship_reparented` warning. Refusal for ships with history is unchanged (`status_identity_conflict`). |
| **F-19** path selection | any of 5 keys selected the strict path; `username + shard_uuid` → `400 ship_guid is required` | strict path iff `ship_guid`, `ship_model` or `player_guid` is present. `username + shard_uuid` uses the legacy path. A `player_guid` never downgrades to legacy, so no ownership check is bypassed. |
| **F-17** unbounded `retry` | infinite loop on a persistent uniqueness violation | `MAX_STATUS_ATTEMPTS = 3`, in both `TradeService.status_by_ship_guid` and `StarTraderShipSync` |
| additive response keys | — | every status response carries `warnings: [{code, message, …}]` and, where a status payload was processed, `location_resolution: applied \| unresolved \| absent \| ignored_in_transit \| ignored_recent_origin` (one value beyond the playbook's list, for the Q1 stale-origin guard). In-flight or stale-origin conflicts also appear as a `stale_location` warning. The v173 `location_sync` key is kept unchanged. |

Unchanged: authentication, all existing response keys, idle and blank-location behavior, HTTP 200 during active/paused travel, no `ShipTravel` writes from status, the 15 000-credit rule (Q7), and wallet semantics.

## Changed files

`app/services/trade_service.rb`, `app/models/shard.rb` (CRLF preserved), `app/services/star_trader_ship_sync.rb`, `db/migrate/20261116020000_add_normalized_channel_uuid_index_to_shards.rb`, `db/schema.rb` (index only).
Tests:
* new `test/controllers/api/status_reliability_test.rb` (6 tests);
* intentional rewrites in `test/services/trade_service_test.rb` (unknown location ×2, unknown shard, idempotency, username collision ×2), `test/controllers/api/trades_controller_test.rb` (unknown location, unknown shard, reassignment with a registered second shard), and `test/services/status_location_sync_test.rb` (identity test registers its target shard).

## Tests actually run

| Command | Result |
|---|---|
| 8 status/travel/sync files (`m04_focus.log`) | **211 runs, 971 assertions, 6 failures, 3 errors**. All are baseline identities: **0 new**, and **1 baseline fixed** (`TradeServiceTest#test_status_treats_same_player_name_with_different_player_guid_as_different_user`) |
| `bin/codex_test test/controllers/api/status_reliability_test.rb` | 6 runs, 19 assertions, 0 failures |
| `bin/codex_test docs/evidence/status-location-time/M00/repro_test.rb` | 7 runs, **1 failure**. R-3, R-4, R-5 and N-01 now pass; R-1 and R-2 still pass; only R-6 (F-13, M05) remains |
| `bin/codex_test` (full) | **645 runs, 6684 assertions, 33 failures, 24 errors**: **0 new, 1 baseline fixed**. The first run exposed one interaction: the M01 audit test fixtured a case-variant shard pair, which M04 now forbids. Its fixture now drops the index inside the test transaction; PostgreSQL rolls the DDL back. After the full run, `pg_indexes` confirmed `index_shards_on_normalized_channel_uuid` was still present. |

## Notes for the M08 merge of `origin/main`

* `main`'s `61331ac` replaced the username test with "rejects a conflicting name without reassigning the original player", which asserts `RecordInvalid`. That contradicts the F-05 contract and must be rewritten during the merge.
* `main` fixes the unsorted ship-key list in the two "keeps response shape" tests. During the merge, their top-level key lists must gain `location_resolution` and `warnings`. They are left untouched here to avoid a conflict and remain baseline failures until then.

## Client compatibility (Q6)

Status codes only became *more permissive* (400/422 → 200), with one exception. **An unknown `shard_uuid` now returns 404 where it used to create a shard. This is the Q3 decision and needs owner awareness:** a brand-new live shard must be registered in Admin › Shards before its players can sync.

## Rollback

Revert the M04 commit. The unique index can stay, since older code never creates case-variant shards except through the removed create-on-miss. If it must go, `rails db:rollback` drops it.
