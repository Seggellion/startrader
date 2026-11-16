# M05 — Unix API instants, paused countdown, and timezone presentation

**Verdict: PASS (2026-11-16).** Decisions applied: **Q5** (integer seconds) and **Q6** (additive only; the legacy `ship.time_remaining` is byte-identical).
Simulation ticks, tick counts, durations, orbital simulation seconds, travel speed (1 Gm/tick, minimum 2), gate quantization `ceil(120 / seconds_per_tick)`, interdiction and resume, and the positional RabbitMQ `ShipArrival` message are all **unchanged**.

## Contract

| Suffix | Meaning | Examples |
|---|---|---|
| `_tick` | point on the simulation tick axis | `departure_tick`, `arrival_tick` (0 = interdicted sentinel), `current_tick` |
| `_ticks` | count of ticks | `remaining_ticks`, `total_duration_ticks` |
| `_seconds` | duration in seconds | `remaining_travel_seconds`, `nominal_travel_seconds`, `travel_time_seconds` |
| `_at_unix` | absolute instant, **integer Unix epoch seconds, UTC**, JSON `null` when unknown | `arrival_at_unix`, `server_time_at_unix`, `updated-at-unix` |
| `_at` | Rails datetime (UTC in the database) | `created_at`, `location_updated_at` |

## Changes

| Change | Where | Notes |
|---|---|---|
| `ShipTravel#arrival_at_unix(current_tick)` | `app/models/ship_travel.rb` | `now + max(arrival_tick − tick, 0) × seconds_per_tick`, recomputed per response and **never stored**. `nil` when paused, completed, or `arrival_tick ≤ 0`, so interdiction never becomes 1970. Arrival decisions still use `arrival_tick <= Tick.current`. It is an estimate: a stalled tick chain moves it forward. |
| `ShipTravel#remaining_travel_seconds(current_tick)` | same | paused-aware duration (F-13): for a paused journey it uses `remaining_ticks_from_arrival` |
| status `travel.arrival_at_unix`; `ship.remaining_travel_seconds`, `ship.arrival_at_unix`; top-level `server_time_at_unix` | `TradeService` | **`ship.time_remaining` unchanged** (Q6) |
| `/api/travel` (new and replayed) `arrival_at_unix`, `server_time_at_unix` | `Api::ShipTravelController#create` | mixed CRLF/LF endings preserved |
| `/api/location` `arrival_at_unix`, `server_time_at_unix` (paused branch: `arrival_at_unix: null`) | `Api::ShipTravelController#location` | |
| `/api/gate_travel` `arrival_at_unix` (`null` once finalized), `server_time_at_unix` | `Api::GateTravelController` | |
| `GET /api/commodities` parallel `"updated-at-unix"` | `Api::CommoditiesController` | the existing ISO-8601 `"updated-at"` is kept unchanged |
| `DisplayTimeHelper#display_time`, `#display_date` | `app/helpers/display_time_helper.rb` (new) | every rendered admin date/time carries a zone label. Display zone = Setting `admin_display_time_zone` (an ActiveSupport zone name), **default UTC**, read once per request. |
| 20 admin views converted | `app/views/admin/**` | removes every unlabelled `strftime` and the **hardcoded Pacific conversion** in `star_bitizen_runs/index` (now the configured display zone). The M01 user page routes through the same helper. |

## Deliberate deviation recorded

**R-6 (discovery reproduction for F-13) keeps failing by design.** It asserts `ship.time_remaining == travel.time_remaining`, which would change the legacy key. Under Q6 the legacy key stays as it was, and the equality is asserted on the new key instead (`ship.remaining_travel_seconds == travel.time_remaining`, in `UnixTimeContractTest`). Migrating the bot to the new key is an owner follow-up.

## Tests actually run

| Command | Result |
|---|---|
| `bin/codex_test test/services/unix_time_contract_test.rb` (new, 7 tests) | **7 runs, 34 assertions, 0 failures**. Covers: integer 10-digit seconds equal to the derived value under frozen time; a stalled tick moving the estimate forward by exactly the elapsed wall time; sentinel and completed → `nil` (never 0); the status legacy key unchanged with the new paused-aware key matching `travel.time_remaining`; integer `arrival_at_unix` on status, location and gate replay; the 13-field Rabbit message unchanged with no Unix instant; UTC default label, PST/PDT across the 2026-03-08 and 2026-11-01 transitions, and the missing label |
| `bin/codex_test` (full) | **652 runs, 6715 assertions, 33 failures, 24 errors**: **0 new**; the M04 fix still holds (1 baseline fixed). Covers the 20 converted admin views, `travel_timing_pipeline_test` and the orbital suites. |

## Rollback

Revert the M05 commit. It adds keys only and makes no schema or data change.
