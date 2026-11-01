# StarTrader jump and travel discovery

Discovery date: 2026-11-01 UTC. **Report-only phase; neither defect has been fixed.** Production access was read-only. No production jumps, ticks, migrations, repairs, restarts, deployments, configuration writes, commits or pushes were performed.

## 1. Executive findings

| Finding / confidence | Symptom → conditions → evidence → mechanism | Correction and verification proposed |
| --- | --- | --- |
| **Confirmed code/design conflict; strong production attribution, not an incident log proof** | Eight persisted production journeys have `arrival_tick=0`; all are paused, incomplete ordinary journeys with interdiction metadata and interdicted ships. `ShipTravel#interdict!` explicitly writes zero (app/models/ship_travel.rb:134–144). All eight saved remaining times exactly match departure + saved duration − pause tick. Local interdiction reproduces the stored zero, worker exclusion and jump rejection. | Keep a positive saved arrival while paused, use explicit pause state and saved remaining duration, update consumers/tests, enforce a database invariant. Verify every writer, raw SQL rejection, pause/resume and historical journeys. Do not automatically resume players to satisfy a constraint. |
| **Confirmed local jump blocker related to paused travel** | Gateway entry calls `ShipAvailability#validate_usable!`; its predicate is `completed_at_tick IS NULL AND (is_paused = true OR arrival_tick >= current_tick)` (app/services/ship_availability.rb:45–49). A paused zero journey returns HTTP 422, `Ship is already in transit.` It is the **paused journey**, not zero alone, that blocks the jump. | Preserve legitimate interdiction restrictions but expose actionable paused/resume state and recovery. Local unpaused-zero control permits another jump and leaves two incomplete rows, proving zero alone is not the blocker. |
| **Confirmed independent local jump defect; production incident linkage unresolved** | Selecting a gateway from another station is accepted. Gate creation changes ship origin but leaves player location behind; arrival only updates the player if it matches the travel origin. The ship arrives in Nyx while the player remains at Ruin Station in Pyro. Next jump is rejected for location mismatch, with **no travel rows and no zeros**. Sources: gate service:40–55,86–95,124–139; arrival processor:43–50. | Resolve the intended remote-gateway rule with the owner, then make departure/player location consistent transactionally. Existing tests explicitly permit gateway selection from a station. Verify jump → arrival → second jump with an already initialized player location. |
| **Confirmed independent local transient rejection** | A jump request that processes an overdue/due arrival reloads the ship but uses a previously loaded player object. It rejects once for the old player location even though the database player and ship locations now agree. Next request succeeds. Sources: ShipAvailability:10–15,52–60 and gate service:29,40. | Reload the authoritative player after lazy completion; verify same-request completion and new departure. |
| **Confirmed route-dependent rejection; incident linkage unresolved** | Production gateway catalog has seven gateways. Stanton → Terra has no reciprocal gateway in Terra. A local equivalent returns 422 `No valid destination Jumpgate found.`, independent of zero rows. | Owner determines whether Terra is deliberately unavailable or a missing catalog route. Validate explicit supported routes and report unavailable routes before submission; do not invent a Terra destination. |
| **Confirmed additional arrival-loss defect locally; no observed production instance** | A RabbitMQ exception rolls back arrival. Tick then runs destructive stale cleanup and deletes the still-due journey, retaining the origin and changing status to floating. Sources: arrival processor:11–23; Tick:50–54; ShipTravel:31–35,177–199. | Preserve failed due journeys, isolate per-row failures and add durable/idempotent event delivery. Regression must prove retry after broker failure reaches the destination exactly once. |
| **Confirmed additional partial-write exposure locally** | Ordinary TravelService commits a positive-arrival row before updating the ship; injected ship-save failure leaves the journey durable. Gateway creation rolls both back. Sources: travel service:43–56 versus gate service:124–139. | One ship-locked departure transaction shared across writers; retain mechanics. Verify failure at each boundary and competing requests. This exposure did not produce zero in the executed reproduction. |

**Relationship:** the defects overlap for interdicted ships, but are not one universal defect. The observed zero population is consistent with the interdiction sentinel. Independent gateway state defects can fail without zero records. No production failed-jump request or externally displayed button was available to tie a particular player report to one branch. The smallest next observation is a sanitized failed request/response with ship identifier, selected gateway, request time and contemporaneous ship/player/travel state.

Impact at the snapshot: eight ships blocked by paused journeys; six have cargo rows. No active gateway journey, valid due journey, duplicate incomplete journey or orphan was present. These are snapshot counts, not lifetime incidence or all players who cannot jump.

## 2. Environment and evidence limits

### Checkout and deployment

- Repository: `/home/dusti/startrader`, Windows `\\\\wsl.localhost\\Ubuntu\\home\\dusti\\startrader`; origin `https://github.com/Seggellion/startrader.git`.
- Branch `codex/terminal-filter-production`; HEAD `e393c2834d774169a8e4541a084668b811a6e1c4`. No checkout, fetch, reset or ref mutation.
- Initial Linux Git state: untracked `.claude/`, `STARTRADER_ORBITAL_CALIBRATION_PLAYBOOK.md:Zone.Identifier`, `STARTRADER_TERMINAL_FILTER_PLAYBOOK.md`, `STARTRADER_TERMINAL_FILTER_PLAYBOOK.md:Zone.Identifier`. Preserved. Separate Claude worktree at `fecb49f` was not used.
- Windows PowerShell host; execution through WSL Ubuntu 24.04.3. Native execution with the UNC working directory failed with `CreateProcessSecurityEnvironment ... 0x80070001`; commands succeeded through `wsl.exe -d Ubuntu --cd /home/dusti/startrader` from a Windows directory. WSL `rg` is unavailable; bounded `grep`, `find`, `nl`, and Git searches used instead.
- Ruby 3.2.2 via rbenv; Rails 8.0.1, PostgreSQL adapter, Minitest; Active Job with Delayed Job. Actual configuration is not the README's stale Redis/Sidekiq getting-started suggestion (config/application.rb; Gemfile.lock; Procfile).
- **Fresh production identity verified** at 14:04:57 UTC: Heroku `star-trader`, app UUID `6b362b75-1732-42a4-9888-669a393f7f82`, domain `startrader.altama.energy`, database add-on `postgresql-metric-14477`; PostgreSQL 16.14. Current v171, succeeded, deployed source **`4d2d7cb97bea19f629a8f71262eaabf10748ebb8`**, created 2026-10-25T02:50:55Z. web.1 and worker.1 both up on v171. Checkout is a later documentation closeout, not the running SHA.
- Executed `git diff 4d2d7cb97bea19f629a8f71262eaabf10748ebb8 HEAD --` for gate controller/service, ShipAvailability, ShipTravel, UserShip, ShardUser, ordinary travel/controller, tick, arrival job/processor: **no differences**. Local causal reproductions apply to those deployed sources; this does not establish an observed incident.
- Instructions/documents read: user-supplied Chrome-only AGENTS.md, README, orbital calibration discovery, travel timing release, terminal filter release, relevant schema/migrations and tests. Bounded in-repository search found no additional AGENTS.md outside dependencies. No browser tests were run; no non-Chrome browser was launched.

### Executed evidence and windows

1. Read-only PostgreSQL repeatable-read snapshot at **2026-11-01 14:04:34 UTC**, tick 746082; repeated snapshot begun around **14:07:29 UTC** (exact server timestamp in evidence JSON). Eight identical travel IDs remained. Connection enforces `default_transaction_read_only=on`, `statement_timeout=10000`, `lock_timeout=2000`; every snapshot ends ROLLBACK. Plain pg client, no Rails production boot/callbacks.
A supplemental read-only trigger/index audit at **14:17:39 UTC** found no non-internal ShipTravel triggers and verified the unique travel GUID index and absence of unfinished-per-ship uniqueness; release remained v171. Its exact queries are included in the retained operator script and supplemental evidence JSON.

2. Bounded `heroku logs --app star-trader --num 500`: 500 lines, **14:03:25–14:08:14 UTC**. Zero gateway router requests and zero `tick_side_effect_failed` lines in this window. This cannot rule out earlier failures or establish lifetime broker health.
3. Local isolated PostgreSQL **18** test database `star_trader_terminal_test`, loopback 127.0.0.1:5432, limited role `startrader_orbital_test`, existing ignored `.env.terminal-test`; single worker, TICK_BOOTSTRAP=false. Test harness prepares and writes this synthetic test database only. Real Bunny connections are prohibited by test/support/no_real_broker.rb.
4. Default test profile first failed passwordless local authentication; the existing explicit test profile worked. No database role/authentication configuration was changed.
5. No external Twitch/chat/client source, failed client payload, historical incident logs, travel audit ledger, historical successful jump row or historical deployed writer/version per row was available. Successful journeys are deleted, so current rows cannot supply a success denominator.
6. Initial `heroku slugs:info` command was unsupported; deployed commit was subsequently verified using the existing read-only Heroku API identity script. No credential was printed.

Retained sanitized evidence: [runtime snapshot](discovery/jump_travel_runtime_sanitized.json). It omits player names, authentication secrets, ship GUIDs, travel GUIDs, individual wallet balances and the database identifier. Raw restricted operator output remains ignored under tmp; do not publish it indiscriminately.

## 3. Travel lifecycle and invariants

### Entry, request and authorization

There is no jump button/action implementation in app/javascript or app/views: the game is driven by external chat/client integrations (README). Therefore absent/disabled button, request formation, response interpretation and external UI refresh remain **unresolved**. Search found server jump handling at `POST /api/gate_travel` (config/routes.rb:108), not ordinary `POST /api/travel`.

Api::GateTravelController:3–27 reads `ship_guid`, optional `travel_guid` (random UUID if omitted), and first present gateway alias among `gateway_name,destination_gateway,destination,to_gateway,to_location`. JSON parsing is in Api::BaseController:9–17. SecretGuidAuth accepts configured shared secret via header or params; missing/wrong secret returns 401 `{"error":"Unauthorized"}`; malformed JSON returns 400. This is integration authentication, not per-player ownership comparison: ship lookup is by GUID and the service requires user, catalog ship and resolved shard. Existing tests prove username is unused and the most recently updated ship is not substituted.

ShipAvailability processes one latest due positive journey first, reloads ship, initializes a missing player location from the ship, then checks unfinished/paused travel, unknown locations and player/ship location equality. These read-looking checks may mutate on the application path; **they were never called against production for this audit**.

Gateway resolution strips a trailing parenthetical suffix, infers target system from `<target> Gateway`, finds the origin in the current ship's system, and reciprocal `<origin-system> Gateway` in the target system. LocationResolver:142–203 scopes case-insensitively by star_system_name, checks exact and normalized matches before ranked fallback; duplicate matches raise. There is no separate route table, range calculation, fuel/credit debit, jump-drive requirement, cooldown, cargo consumption or docking-state predicate in this service. Catalog visibility/availability flags are not enforced by gateway validation; validation checks the normalized name suffix only. These absent checks are current behavior, not permission to invent new mechanics.

Ordinary controller resolves destinations within the current system and rejects cross-system travel (api/ship_travel_controller.rb:66–82). An external client using this endpoint for a jump can therefore fail, but **no such production request was observed**.

### Calculation, departure and persistence

| Writer | Exact saved values / transaction | Evidence |
| --- | --- | --- |
| Ordinary TravelService#call | Capture one departure tick; physical composed Gm separation; `max(ceil(distance_Gm / 1.0),2)`; arrival = departure + duration. Creates ShipTravel, then ship status/location and player location, **without encompassing transaction or ship lock**. Default travel kind NULL. | app/services/travel_service.rb:19–56; travel_time_calculator.rb:11–12; lib/travel_timing.rb:4–11 |
| GateTravelService#create_gate_travel! | Capture `start_tick || Tick.current`; duration = `ceil(120 / Tick.seconds_per_tick)`; arrival = departure + duration; kind `gate_travel`. Travel and ship update in one transaction; availability check outside it, no ship lock. Does not align initialized player location to a selected remote origin gateway. | app/services/gate_travel_service.rb:118–146 |
| ShipTravel#interdict! | One model update sets paused, paused tick, saved nonnegative remaining arrival distance, count and last interdicted tick, **arrival=0**. Already-paused returns unchanged. Controller's subsequent ship status update is separate. | app/models/ship_travel.rb:134–144; api/ship_travel_controller.rb:190–200,241–248 |
| ShipTravel#resume! | Requires paused; remaining.to_i, clamps <=0 to 1; resets departure to current tick, arrival = current + remaining and duration = remaining, clears pause. Controller ship-status update separate. | app/models/ship_travel.rb:149–162; api controller:218–225,288–293 |
| Admin generic create/update | Calls ShipTravel.new/save/update, but copied strong params require `location` and permit Location attributes, **not travel timing or required associations**. It is broken generic CRUD, not an observed functional zero writer. | app/controllers/admin/ship_travels_controller.rb:11–16,26–35,65–96 |

Writer search covered app, lib, db and script for arrival assignments, creates, raw SQL, imports, bulk writes and service callers. No NPC/import/seed/bulk arrival writer found. Tests/fixtures create arbitrary timing by design. Ordinary service also has a legacy caller at app/controllers/moves_controller.rb:14 missing required travel_guid; the route targets `api/moves` (routes:120–122) while the file defines top-level MovesController, contains byebug and undefined user variables. This is another legacy endpoint problem, not evidence about the real jump caller. No non-internal live ShipTravel trigger exists (supplemental pg_trigger audit); no arrival timing default was found in live columns or tracked migrations; external/manual SQL cannot be excluded by source search. Tick's raw SQL writes ship **status**, not arrival.

Migrations: 20250226151138 creates non-null integer departure/arrival without arrival default, FKs to ship/locations; 20250819034413 adds duration/pause/interdiction metadata; 20250824034809 adds kind; 20260616000000 adds GUID/unique index/completion; 20260818120000 adds broker with prod default. Live columns and constraints were inspected before auditing rows and agree with the relevant schema (db/schema.rb:445–469). No positive timing CHECK, no uniqueness constraint for one incomplete journey per ship. Arrival integer is signed 32-bit; overflow raises rather than wrapping to zero in PostgreSQL. Omission produces NULL violation, not automatic zero. No model timing numericality validation exists; alternate writers remain unprotected.

### Tick contract and completion

- Global persisted `ticks.current_tick`, not per ship, route, shard, orbital clock or travel-relative counter. `Tick.instance` uses first_or_create(current_tick:0, sequence:1); current_sequence is separate (app/models/tick.rb:22–32). No singleton uniqueness constraint was established. Live: one row id 34, current_tick 746082 and sequence 746083 in first snapshot.
- `OrbitalState.current_tick!` reads oldest tick by id and raises if missing, unlike Tick.current which may create tick zero (orbital_state.rb:8–9). Normal application retains ticks through restarts; no wall-clock catch-up/reset in the inspected runner. Privileged manual tick endpoints exist (routes:103–104); none were invoked. They and multiple tick rows need separate operational controls; no evidence they caused these records.
- Tick.increment! locks tick row and increments both counters in a transaction while running economy. After commit it runs arrival, stale cleanup, three-tick ship-status correction and broadcast as separately rescued side effects (tick.rb:34–58,128–135).
- TickRunner uses PostgreSQL advisory lock 4294967291; TickJob ensures next job after configured seconds, even after failure; TickWatchdogJob/TickControl repair the chain. Queue uses Delayed Job; no per-journey scheduled job is created by departure. Tick completion time + 15 seconds is nominal spacing, not guaranteed exact wall cadence or downtime catch-up.
- Live seconds_per_tick=15, hours_per_tick=168, interdiction_window_percent=15. Tick.seconds_per_tick validates finite positive input with fallback 15 (tick.rb:8–16,138–145). Ordinary rate **1 Gm/tick**, ceiling, minimum two ticks. Orbital simulation seconds govern geometry, not scheduler seconds. Gateway is independently **120 seconds rounded up to whole ticks**, eight ticks at 15 seconds; four at the fixtures' 30 seconds. Never apply ordinary distance formula to gateways.
- Arrival is an **absolute tick**, duration and paused remaining are relative tick counts. At tick zero normal minimum arrival is 2 and gateway arrival is 8; zero current tick does not produce zero arrival. Current mechanics provide positive duration for supported ordinary/gate starts; zero physical separation still takes two ticks. An instantaneous future mechanic could have zero duration at positive departure without violating positivity, but no such rule is introduced here.
- ShipArrivalJob:8–12 selects unpaused, incomplete, nonzero arrival <= captured current tick, so due-now and missed-positive deadlines work. Processor due_for_arrival? additionally requires positive arrival; negative rows would be selected but not finalized. Zero is explicitly excluded, not a Ruby truthiness effect (Ruby considers 0 truthy).
- Processor locks travel row, rechecks due, writes ship.location_name and status from destination classification, conditionally updates ShardUser.last_location, publishes to saved RabbitMQ broker, destroys travel (arrival_processor.rb:8–27,34–50). Ship location is authoritative through **name**, not current_system_id; player location is serialized JSONB last_location resolved by name (user_ship.rb:11; shard_user.rb:63–85). Arrival/completion is not retained as a durable completed row in this path.
- External publication is inside the database transaction but cannot be rolled back by PostgreSQL. Crash after broker send before commit can duplicate publication on retry; external consumer deduplication was not inspected. Concurrent processors serialize on journey row; missing/deleted row is rescued.
- Tick stale cleanup selects every unpaused positive due journey even if incomplete; it destroys it without completing destination and may set ship floating (ship_travel.rb:31–35,177–199). This is why retry safety must be addressed before any recovery relies on the worker.

### States, consumers and desired invariant

Current states: origin ship + no journey → unpaused unfinished journey/in_transit → paused unfinished journey/interdicted → resumed unfinished journey/in_transit → destination ship + deleted journey. Cancellation destroys active journey and may set floating, retaining stored origin; no asset refund logic in that path. Cancellation API uses ShipTravel.active, excluding paused rows (api controller:369–378); it is not a general paused recovery tool.

Sentinel/paused consumers:
- ShipTravel.active and in_flight_now:19–26 and UserShip.active_travel:16–18 exclude paused and expire at arrival >= tick.
- due_for_arrival?:114–115, stale_after_arrival:31–34, arrival job:8–10, ShipAvailability.process_due_arrival!:52–60, API process_due_arrival_for:504–510 explicitly avoid zero or require positivity.
- ShipAvailability.in_transit?:45–49 and API travel_in_progress?:713–716 include paused rows regardless of arrival.
- Tick.correct_ship_statuses:90–108 preserves paused status; unpaused overdue rows are treated differently.
- TradeService.active_status_travel/status_travel_payload:481–505 uses saved remaining for paused rows and exposes is_paused, unlike active_travel-only endpoints.
- API location:139–181 exposes paused separately; LocationsController#show:21–27 only reports active_travel, so paused can look idle. Admin travel views show raw arrival and ship edit displays metadata.
- Resume replaces sentinel; interdiction windows/progress/countdowns use absolute arrival for unpaused travel. Do not simply replace the zero with a positive deadline while removing pause predicates.

**Required final database invariant:** every persisted ShipTravel.arrival_tick is a non-null integer **>0**, including paused rows, legacy rows and alternate writers. For new ordinary/gate departures, require arrival = captured departure + saved duration, duration >0, departure >=0, within column range. For paused rows preserve original positive schedule plus explicit pause/remaining fields; do not require frozen arrival to remain in the future. For resume retain established remaining-leg reset semantics after owner review of missing/zero remaining policy. The general constraint arrival > departure is appropriate to current positive-duration writers, but historical rows and any future zero-duration rule must be audited before imposing it globally. Valid overdue unpaused positive records must remain pending/retryable until successful completion; they are not garbage.

History: explicit zero sentinel exists in **46a1ee5 (2025-08-21)** alongside interdiction. GateService introduced in **1505093 (2026-07-01)** already accepted remote gateway selection. Availability added to it in **09862f0 (2026-07-03)**. These establish source ancestry, not which production release wrote a particular record. Travel timing release explicitly preserved paused sentinels and its existing regression asserts zero; this earlier compatibility decision conflicts with the present owner's invariant and must change.

## 4. Jump failure analysis

All following HTTP actions were **local synthetic integration requests**, never real player jumps.

### Trace A: representative paused journey blocks new jump

Fixture ship `target-ship-guid`, at Pyro Gateway (Stanton), reciprocal Stanton Gateway (Pyro), tick 10, seconds/tick 30. POST /api/gate_travel with test secret and ship GUID succeeds: departure 10, duration 4, arrival 14. Interdict at 10 persists paused=true, arrival=0, remaining=4. Arrival job leaves it unchanged. Same POST returns **422**, body status=error/message=`Ship is already in transit.`; still one row, ship origin unchanged.

First blocking decision: ShipAvailability.in_transit? paused OR future predicate. This is an established prohibition on abandoning an unfinished paused trip; the misleading transit wording and sentinel violate intended representation, not proof that jumping while interdicted should be allowed. Control with identical **unpaused** zero: processor skips it, availability fails to recognize it at positive tick, second POST succeeds and leaves two incomplete journeys. Thus eliminating zero alone will not authorize a paused jump, and allowing zero rows to be ignored is unsafe.

### Trace B: remote-gateway departure causes persistent player mismatch

Setup ship AND initialized player at Ruin Station (Pyro); gateway Nyx Gateway (Pyro); reciprocal Pyro Gateway (Nyx); tick 10. POST gateway_name=Nyx Gateway returns 200 with arrival 14, ship now at the selected origin gateway/in_transit, player still Ruin Station. At due tick, arrival job succeeds and deletes travel, ship becomes docked at Pyro Gateway (Nyx), player remains Ruin Station. Next POST returns **422**:

`Ship is at Pyro Gateway (Nyx), but player is at Ruin Station.`

First incorrect durable transition: gate departure updates ship origin without player-origin alignment; later completion's origin guard correctly refuses to move a player that appears elsewhere. This is not stale UI or worker selection, and no zero is involved. Existing tests starting with blank player location miss it. Control departing while player and ship are actually co-located at gateway completes (also at arrival+3), updates player, and permits return jump.

Owner decision: preserve remote selection as an intentional shortcut (existing tests suggest this contract), or require travel to the gateway before jumping. Either choice needs explicit errors and atomic state. Do not remove arrival's origin guard wholesale; it protects players who legitimately changed location during transit.

### Trace C: lazy completion rejects a valid request once

Player/ship co-located at gateway, positive pending trip due now. Without invoking worker first, POST next jump. Availability processes the due arrival; persisted ship and player both reach Pyro. Its cached player instance still says Stanton and response is **422** with old-location mismatch. Immediate retry returns 200. Unlike B, database state already succeeds; server's in-memory validation is stale. Reload after completion is the narrow correction.

### Trace D: route topology and legitimate failures

Live catalog: Stanton ids 1410 Pyro, 1411 Nyx, 1412 Terra; Pyro ids 1436 Stanton, 1440 Nyx; Nyx ids 1441 Stanton, 1442 Pyro. Reciprocal routes exist among Stanton/Pyro/Nyx. No Terra gateway destination exists. Local missing-reciprocal fixture returns 422 `No valid destination Jumpgate found.` with zero rows created. Baseline tests also cover wrong/missing secret, missing ship, invalid origin, unavailable gateway and ambiguous reciprocal catalog.

No known successful production jump control was retained; live rows are all ordinary and successful journeys are deleted. Successful intended jump path was reproduced locally. Production button behavior, endpoint used by reporting clients, payload aliases, account/route distribution and exact first failure in a real report remain unresolved. Request capture, not production trial travel, is the next diagnostic.

## 5. Zero-arrival analysis

Executed snapshot counts (whole live table, eight rows; bounded joins/sample LIMIT 12):

| Timing / state | Count |
| --- | ---: |
| Total persisted rows; arrival=0 | 8; 8 |
| Zero paused unfinished / unpaused / completed | 8 / 0 / 0 |
| Zero ordinary kind NULL / gate_travel | 8 / 0 |
| NULL / negative / positive-before-departure arrival | 0 / 0 / 0 |
| Valid positive overdue unpaused incomplete | 0 |
| Ships with >1 incomplete journey | 0 |
| Missing ship / origin / destination FK targets | 0 / 0 / 0 |
| Zero rows with missing/negative saved remaining or missing pause tick | 0 |
| Rows satisfying pause_tick + remaining = departure + duration | 8 |

Every ship has status interdicted, location_name equal to travel origin, and saved broker **dev**. This means development **broker routing on the production database**, not proof of test accounts or permission to discard assets. Six rows have cargo entries; no fuel/credit consumption occurs in these start/interdict/resume services. Wallet state was read for recovery context and omitted from shareable evidence. No refund can be inferred.

| Travel id / ship id | Departure / saved duration / pause / remaining | Route / relevant state |
| --- | --- | --- |
| 4607 / 640 | 391226 / 23 / 391247 / 2 | Lorville → Rayari Anvik Research Outpost; cargo rows 0 |
| 5007 / 455 | 678312 / 27 / 678314 / 25 | Terra Gateway (Stanton) → Seraphim Station; used SCU 696, cargo rows 1 |
| 5028 / 426 | 689360 / 35 / 689363 / 32 | Terra Gateway (Stanton) → Pyro Gateway (Stanton); used SCU 12288, cargo rows 1 |
| 5042 / 504 | 689725 / 7 / 689731 / 1 | MIC-L2 Long Forest → ARC-L5 Yellow Core; cargo rows 1 |
| 5043 / 507 | 689806 / 27 / 689810 / 23 | Terra Gateway (Stanton) → Seraphim Station; cargo rows 1 |
| 5071 / 767 | 702296 / 47 / 702303 / 40 | HUR-L2 Faithful Dream → MIC-L4 Red Crossroads; cargo rows 0; **decoded player payload instead names HUR-L1 Green Glade** |
| 5090 / 551 | 723686 / 68 / 723695 / 59 | HDMS-Woodruff → Nyx Gateway (Stanton); cargo rows 1 |
| 5121 / 506 | 734966 / 66 / 734970 / 62 | Nyx Gateway (Stanton) → HDMS-Anderson; used SCU 50, cargo rows 1 |

Player location is a serialized store within JSONB, not a nonexistent current_location_id. Audit read raw last_location then decoded nested JSON strings for presentation; seven payloads match origin, row 5071 does not. This is separate contrary player evidence requiring investigation, not authorization to teleport that player.

Created-at range **2026-08-31 02:18:49 to 2026-10-30 15:06:39 UTC**; updated-at range **2026-08-31 02:24:00 to 2026-10-30 15:07:38 UTC**. Rows 5090 and 5121 postdate v171 deployment. Timestamp, pause metadata and current reproducible writer strongly support continued sentinel behavior through Oct 30; no audited transition to zero was observed during this Nov 1 window. Two snapshots do not prove a current creation rate or absence of transient new/deleted journeys.

### Creation versus survival

Confirmed writer: interdict! writes zero in one UPDATE; original creation already had a computed positive arrival. Saved remaining arithmetic is consistent for all observed records, including old journeys that predate current ordinary timing. This is a materially better explanation than a zero default, omitted field, duration confusion or rounding. It remains **likely production attribution**, because no historical write audit identifies the exact call.

Survival: pause intentionally excludes normal arrival and stale cleanup forever until resume/cancel policy acts. Even an unpaused zero is excluded explicitly; positive-only due_for_arrival? adds another guard. No exact-tick equality prevents overdue processing. Active scopes hide paused records from some UI/API consumers, while availability still blocks departure. The resulting apparent limbo is understandable without a dead worker.

Counterevidence/limits:
- All sampled arrivals are stored integer zero, not missing JSON/UI fallback.
- No zero arrival default exists. Normal duration minimum and positive gateway calculation at tick zero do not emit zero. Nonfinite/negative distance raises before insert.
- Injected ordinary partial failure leaves a **positive** row; gateway transaction rolls back. Neither proved a zero-creation route.
- No duplicate, orphan or positive overdue population in live snapshot; none explains these eight.
- Racing requests/stale overwrites remain structural risks because no ship lock/unfinished uniqueness is present; concurrent race was **not** reproduced. No evidence of race-induced zeros.
- Pause/status controller writes are not one transaction; interruption can leave a paused row with old ship status, but all eight live statuses are consistent.
- Model/DB alternate explicit writes can accept zero; no bulk/import/NPC path using that capability was found. Historical/manual writers remain possible.
- All current zeros are ordinary; gate timing is not their observed origin.

## 6. Reproductions

### Commands executed and isolation

From WSL repository root:

```sh
bin/codex_db_doctor --require-connection
# Failed default local passwordless auth; no environment repair attempted.

CODEX_ENV_FILE=.env.terminal-test bin/codex_test \
  test/controllers/api/gate_travel_controller_test.rb \
  test/models/ship_travel_test.rb \
  test/jobs/ship_arrival_job_test.rb \
  test/services/travel_timing_pipeline_test.rb
# PASS: 52 runs, 954 assertions, 0 failures/errors/skips; seed 44188.

CODEX_ENV_FILE=.env.terminal-test bin/codex_test \
  docs/discovery/jump_travel_discovery_test.rb
# PASS: 30 runs, 133 assertions, 0 failures/errors/skips.
# Includes 20 existing gateway integration cases plus 10 discovery cases.
```

The final retained-path command was rerun after packaging (seed **35665**, 30 runs / 133 assertions, all passing). Tests use transactional synthetic fixtures, fixed database ticks and the existing real application services/jobs. No wall waits. Gateway tests directly assign synthetic due ticks to isolate selection/completion; the **separate timing pipeline suite** drives actual queued TickJobs through Delayed::Worker under controlled virtual time, fake broker transport, real arrival logic and real timing. These are different evidence strengths and are not production timing observations.

| Scenario / expected behavior under intended design | Actual executed outcome |
| --- | --- |
| Eligible gateway departure → persisted journey → due-now arrival | Existing baseline passes; tick10→14 at 30 sec; correct ship, origin, destination, kind, pending status; arrival deletes row and sends one report |
| Stranded paused ship retries jump | Zero persisted by real interdict!, skipped by real job, 422 transit rejection; resume restores tick14 |
| Same zero but unpaused | Job skips; new jump succeeds; two incomplete rows. Confirms pause linkage and alternate-invalid-row risk |
| Remote-station gateway choice then second jump | First 200 and actual arrival; player remains previous station; second 422; zero journeys left |
| Co-located gateway success, missed by three ticks, processor retry | Correct ship/player destination; one report despite two job executions; return jump accepted |
| Due arrival processed inside next request | First request 422 with stale player; persisted location correct; immediate retry 200 |
| Duplicate sequential start | First 200, second 422, one row; no resource debit. This is not full concurrent/idempotent success replay |
| Failure between create and ship update | Injected exception: gateway rolls back journey; ordinary path leaves one positive journey and old ship status |
| Tick zero / min / invalid calculations | Gateway arrival8 at departure0 and 15 sec/tick; ordinary zero-distance minimum2; NaN/negative distance raises |
| Broker failure through actual Tick.increment! | Arrival rolls back; subsequent cleanup destroys row, ship/player retain origin, ship becomes floating |
| Missing reciprocal route | Eligible ship gets 422 and no row; no zeros involved |

Initial standalone reproduction load lacked `minitest/mock` (existing suite loaded it transitively); fixed the **discovery harness only**. An initial missing-reciprocal fixture accidentally retained the baseline Terra counterpart and returned 200; removed that synthetic counterpart, then observed expected 422. These were harness setup corrections, not production changes. Passing characterization assertions intentionally describe defects; they must be replaced by desired-behavior regression assertions during implementation.

Retained additions:
- This report.
- [Separate reproduction harness](discovery/jump_travel_discovery_test.rb), outside production app and normal test tree; reuses existing fixture setup.
- [Read-only operator audit](discovery/read_only_travel_audit.rb), standalone pg, exact executed SQL, production read-only options, no embedded credentials. It writes restricted raw output to tmp/jump-travel-runtime.json; sanitize before sharing.
- [Sanitized runtime evidence](discovery/jump_travel_runtime_sanitized.json).

Ignored local files created: tmp/jump_travel_runtime.rb, tmp/jump_travel_discovery_test.rb, tmp/jump_discovery_extend.py, tmp/jump_discovery_fixture.py, tmp/jump_discovery_package.py, tmp/jump_discovery_logs.py, tmp/jump_discovery_trigger.py, tmp/jump_travel_trigger_audit.rb; tmp/jump-travel-{runtime.json,runtime-output.log,identity.json,log-summary.json,baseline.log,repro.log,final-repro.log,trigger-index-audit.json}. Temporary write-probe file removed. Test fixtures rolled back by harness; no production cleanup necessary. No normal application source or test file changed. Full suite and browser/client end-to-end qualification were **not** run.

## 7. Repair design and recovery plan

### Workstream A: prevention and jump behavior

1. Shared travel lifecycle boundary: validate integer tick/positive arrival before persistence, retain ordinary 1 Gm/tick minimum2 and gateway ceil(120/seconds) independently. Require explicit pause state; interdiction retains last positive schedule and saves remaining; resume schedules the remaining leg. Preserve saved broker, destination, cargo and historical duration. Update old sentinel assertions and status/error payloads together.
2. Lock UserShip and relevant ShardUser in a consistent order, recheck authoritative unfinished journey inside a single transaction, create journey and update ship/player atomically. Model association caches must be refreshed after lazy completion. Decide remote gateway semantics before changing departure location policy. Apply the same boundary to ordinary and gateway requests, interdiction/resume, cancellation and supported admin tools.
3. Request idempotency keyed by travel_guid/ship and immutable destination: same request returns existing consistent result; changed payload with same key gives explicit conflict. Add database uniqueness for at most one **incomplete** journey per ship after auditing/cleaning duplicates. Existing GUID unique index alone does not serialize different GUIDs on one ship.
4. Arrival must retry incomplete due records rather than delete them on failure. Remove destructive cleanup as automatic substitute for completion; audit stale completed records separately. Isolate each journey's error so one broker cannot starve the batch. Separate authoritative arrival transaction from publication with a durable outbox and travel/event idempotency keys, or document a provable equivalent. Exactly-once external effects require consumer cooperation; a database lock alone is insufficient.
5. Make errors distinguish paused, location mismatch, missing route, authentication, conflict and internal processing failure; external client must display actionable message and refresh authoritative state. Do not expose secrets or raw exceptions to users.
6. **Database protection:** PostgreSQL `CHECK (arrival_tick > 0)` plus existing NOT NULL protects all writers, not just model validation. Prefer named CHECK added **NOT VALID** only after zero-writing code is retired everywhere. PostgreSQL still enforces NOT VALID on new/updated rows: an old paused zero row can fail unrelated updates until repaired. Therefore first deploy compatible code able to read legacy zeros and preserving positive pause arrivals, stop old writer processes through the separately approved deployment, dry-run/backfill explicitly classified old timing, then add/validate constraint in bounded steps. A NOT VALID phase before cleanup is possible only with tested compatibility for every legacy-row update; do not casually assume it tolerates old updates.
7. Validate constraint against snapshot rows, verify all writers reject zero/negative/raw SQL, then validate CHECK. Audit historical timing relationships before adding stronger checks. Inspect remaining legacy rows at every gate; do not weaken positivity to exempt paused records.

### Workstream B: existing-player recovery

Two separate actions: **representation repair** of invalid timing while preserving interdiction, and any later **gameplay decision** to resume/cancel/complete. Positive backfill does not authorize arrival.

| Recovery class | Evidence required / candidate scope | Proposed action, not executed |
| --- | --- | --- |
| Trustworthy reconstructable schedule | Saved departure, duration, pause tick, remaining, count, destination/ship and no conflicting event. All eight match the original schedule arithmetic with count1, positive remaining; historical versions should be verified before approving batch | Candidate paused backfill to **saved departure + saved duration**, preserving paused flag, pause tick, remaining and ship state. This reconstructs the prior schedule, not current geometry. Independently check saved arithmetic/range, writer semantics and asset/player conflicts. |
| Authoritative completion supported | Arrival ledger/outbox/broker consumer acknowledgement plus destination state and no conflicting journey | Finalize/reconcile once with an audit record. **No live row currently has this evidence**. Merely being old or having an old scheduled arrival is insufficient while paused. |
| Resume/cancellation supported by established rules | Owner/player intent and supported interdiction resolution rule; trustworthy saved remaining | Approved resume can use actual recovery tick + saved remaining under existing semantics, not blanket current+1. Test ship/player origin guard and separate status writes. Cancellation requires an explicit paused cancellation policy; existing active-only endpoint excludes these rows and status cleanup does not reliably clear interdicted status. No automatic refund. |
| Insufficient or contradictory evidence | Missing historical timing, moved player, later cargo/economy effects, unknown location or duplicate completion | Quarantine/report; request exact owner disposition. Row **5071** needs explicit player-location review before a gameplay action; seven matching payloads still do not establish consent to resume. |

Saved old duration is the historical input; do not use today's 1 Gm/tick or catalog to recalculate old trips. For all eight, `departure+duration = pause+remaining`; representation can be proposed without applying contemporary orbital rules. If evidence of earlier resume, rate migration or manual edit contradicts this identity, use historical deployment/version logs or quarantine instead. Old writer timestamps alone cannot determine policy version.

### Proposed dry run and controlled application

**All later production mutation/deployment steps require separately scoped authorization; this discovery did not perform them.**

- Dry run identifies exact travel/ship/shard-user ids, kind, from/to ids, saved ticks/pause metadata, player payload, ship status/location, saved broker, cargo quantities/values, wallet/inventory checksums, dependent jobs/events, proposed action/reason/evidence version. Include current values + expected before-hash + proposed after-state; no credentials.
- Re-read entire scope at execution; do not use this report's list as an unconditional target list. Initial candidates 4607,5007,5028,5042,5043,5071,5090,5121. Classify each; generate no-action and owner-decision rows too. Detect newly created invalid journeys and conflicting positive journeys.
- Capture verified database backup/snapshot and a targeted immutable before-image/audit record immediately before approved writes. A full database restore is unsuitable for isolated recovery because other players continue trading.
- Small batches (e.g. <=20 candidates, initially one approved canary) with deterministic ship→player→journey locking shared with application code. Under lock require same ids, timing, update timestamp/content hash, incomplete/paused state and no other active journey; changed rows skip and reclassify. Use short lock/statement timeouts. No production tick acceleration or queue deletion.
- Idempotent recovery ledger unique by journey+repair version/action; commit before/after audit with the mutation in one transaction. No resource changes for timing-only backfill. Preserve six cargo-bearing ships, cargo rows, SCU, wallet, inventory, destination and broker. Later resume/completion has independent idempotency and notification keys.
- Verify invariant and unchanged assets/counts, one unfinished journey per ship, proper paused status, no unintended destination/player movement and no duplicate notification. For approved resume, verify worker eventually reaches saved destination using remaining ticks and updates player only when authoritative preconditions hold.
- Rollback limits: timing-only repair may restore its before-image **only if no intervening gameplay/state change**, and a validated positive constraint means restoring zero is not an acceptable steady state. Prefer roll-forward correction. Do not roll back completion/publication by restoring an old travel row: external deliveries and player trades are not reversible by row restore. Broker duplication/refund risk requires ledger and owner reconciliation.
- Stop batch on changed player location, cargo/wallet differences, duplicate journey/event, missing historical input, overflow, unexpected writer creating zeros, constraint conflict, unexpected locks or broker failure. Row 5071 is explicitly withheld from automatic gameplay recovery until reviewed.

## 8. Proposed milestones

| Milestone / dependency | Concrete deliverable and acceptance | Rollout / rollback / stop condition |
| --- | --- | --- |
| **M1: bounded implementation specification and regression-first lifecycle repair** | Resolve remote gateway behavior and paused lifecycle intent; convert the ten characterization cases into expected-behavior regressions; fix remote player alignment and lazy stale player; prevent zero writes; atomic/locked departures; preserve failed arrivals for retry. Keep timing formulas unchanged. Add concurrent different/same-GUID request tests, interrupted interdict/resume, broker rollback/retry. | Local synthetic DB only first. Acceptance: second jump succeeds with coherent ship/player, paused trip remains explicitly paused with positive arrival, zero never saved by supported writers, broker failure retains retryable journey, assets unchanged. Stop if owner rule is undefined or these guarantees conflict. No production recovery in M1. |
| **M2: durable completion/idempotency and database compatibility** (M1) | Outbox or equivalent event protocol, consumer dedup agreement; ship uniqueness and positive CHECK migrations rehearsed against sanitized legacy cases. Dry-run legacy updates under NOT VALID and validated states; raw SQL bypass tests. | Separate application/schema deployment plan. Do not deploy constraints before legacy-update compatibility and old-writer retirement. Rollback code must understand positive paused schedules; old sentinel writer cannot run under the constraint. Stop on incompatible consumer or legacy writer. |
| **M3: read-only recovery manifest and owner decisions** (can start alongside M1, final manifest after M2 design) | Fresh scoped audit, per-record evidence/action, historical saved timing review, row5071 disposition, resource hashes and backup/rollback rehearsal. | No player writes; approval artifact must name rows/actions, including preserve-paused versus resume/cancel. Stop uncertain rows individually, never fill with a generic deadline. |
| **M4: separately approved production prevention deployment** (qualified M1/M2, compatibility plan) | Exact reviewed SHA, fresh app/domain/db identity, backup, Chrome-only client acceptance if UI involved; versioned compatible writers; read-only live validation. | No implicit deploy in discovery. Observe no new zeros/error spikes. Rollback to compatible code only; never restore sentinel writer under enforced CHECK. Stop on identity drift, schema mismatch, inconsistent state or failed arrival retry. |
| **M5: separately approved data recovery and constraint validation** (M3, M4) | Canary then locked batches; immutable ledger, verify assets, preserve pause or execute specifically authorized gameplay recovery. Add/validate positivity and unfinished uniqueness in the rehearsed order. | Observe actual outcomes and broker dedup without synthetic production travel. Rollback only safe untouched representation changes; reconcile irreversible effects. Stop conditions listed above. |
| **M6: follow-up observation and handoff** | Bounded zero/overdue/duplicate/error counts, worker health, real authorized journey results if available, external UI error/refresh verification and historical audit retention. | Quiet observation does not prove lifetime success. Close only with zero invalid persisted rows, compatible enforced writers, reviewed recovery dispositions and no unexplained lost arrivals. |

M1 should not silently grow into catalog changes, orbit calibration, economy mechanics, authentication redesign, historical cleanup or deployment. Independent route/catalog decisions and external integration work require explicit acceptance criteria.

## 9. Handoff evidence

### Exact source map

- app/controllers/api/gate_travel_controller.rb:3 — request, success JSON and broad 422 rescue.
- app/controllers/api/base_controller.rb:9; app/controllers/concerns/secret_guid_auth.rb:12 — parsing/auth.
- app/services/gate_travel_service.rb:26,40,86,97,105,118,142 — complete jump path.
- app/services/location_resolver.rb:142,181,195 — scoped/normalized origin and reciprocal lookup.
- app/services/ship_availability.rb:10,38,45,52,67 — lazy arrival, equality and paused blockers.
- app/services/travel_service.rb:19; app/services/travel_time_calculator.rb:11; lib/travel_timing.rb:4 — ordinary formula and nontransactional writes.
- app/models/ship_travel.rb:19,31,114,134,149,177,185 — scopes, sentinel/resume, destructive cleanup.
- app/models/user_ship.rb:11,15; app/models/shard_user.rb:63,75 — authoritative names/payload.
- app/jobs/ship_arrival_job.rb:4; app/services/ship_travel_arrival_processor.rb:8,43 — selection, completion and player guard.
- app/models/tick.rb:22,34,90,128; app/services/tick_runner.rb:8; app/jobs/tick_job.rb:4,51; app/jobs/tick_watchdog_job.rb — clock, locks, queue, side-effect handling/recovery.
- app/controllers/api/ship_travel_controller.rb:13,139,190,218,241,288,369,504,713 — ordinary API, paused UI, duplicate pause/resume, cancellation and lazy completion.
- app/services/trade_service.rb:481; app/controllers/locations_controller.rb:21 — contrasting status consumers.
- db/schema.rb:445; db/migrate/20250226151138_create_ship_travels.rb:3; db/migrate/20250819034413_ship_slug.rb:15 — schema and pause history.
- test/controllers/api/gate_travel_controller_test.rb:140; test/services/travel_timing_pipeline_test.rb:175 — existing success fixtures and sentinel-preservation assumptions.

### Executed diagnostic commands / SQL

Exact **executed** queries are retained in [read_only_travel_audit.rb](discovery/read_only_travel_audit.rb). They inspect live triggers/indexes, columns/constraints, ticks/settings, full-table aggregate counts, kind/pause/completion/date groups, a LIMIT12 sample with ship and locations, LIMIT30 duplicate ship groups, orphan counts, overdue positive journeys, ship-state groups, LIMIT80 gateways, LIMIT12 player/cargo context, saved-time consistency and TickJob aggregate state. Snapshot uses one repeatable-read transaction, server-side read-only defaults and bounded timeouts; there is no Rails mutation path.

To reproduce the read-only audit with existing authenticated operator access (**proposed rerun**, not necessary to infer new results here):

```sh
bin/codex_exec bundle exec ruby docs/discovery/read_only_travel_audit.rb
# Credentials fetched in memory from configured Heroku app; never print DATABASE_URL.
# Output is restricted raw data in tmp/jump-travel-runtime.json. Sanitize before sharing.
```

Representative **executed** sanitized SQL, under that read-only transaction:

```sql
SELECT column_name,data_type,is_nullable,column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='ship_travels'
ORDER BY ordinal_position;

SELECT count(*) total,
 count(*) FILTER(WHERE arrival_tick=0) zero,
 count(*) FILTER(WHERE arrival_tick IS NULL) nulls,
 count(*) FILTER(WHERE arrival_tick<0) negative,
 count(*) FILTER(WHERE arrival_tick>0 AND arrival_tick<departure_tick) backwards
FROM ship_travels;
-- 8,8,0,0,0

SELECT user_ship_id,count(*) FROM ship_travels
WHERE completed_at_tick IS NULL GROUP BY user_ship_id
HAVING count(*)>1 ORDER BY user_ship_id LIMIT 30;
-- zero groups

SELECT count(*) FILTER(
 WHERE paused_at_tick+remaining_ticks_from_arrival=departure_tick+total_duration_ticks
) matching_original_arrival,
count(*) FILTER(
 WHERE paused_at_tick IS NULL OR remaining_ticks_from_arrival IS NULL
 OR remaining_ticks_from_arrival<0
) bad_pause_fields
FROM ship_travels WHERE arrival_tick=0;
-- 8,0
```

**Proposed next diagnostics, not executed/results:**
1. Ask reporting integration for one failed request: timestamp, endpoint, gateway input, ship identifier, HTTP status/body, UI message. Redact shared secret/player names. Read-only correlate the journey/ship/player using the audit sample joins filtered by that ship, LIMIT5; capture whether rejection was before request, 401, 422 paused, missing reciprocal, mismatch or lazy-completion retry.
2. Retrieve historical interdiction/resume/arrival/outbox or consumer events for the eight exact travel IDs/GUIDs over their create→pause windows, if retained. Current bounded logs cannot supply them. Verify version semantics rather than infer from dates.
3. For row5071, read the player's location-change history and later ship/asset events to explain HUR-L1 versus HUR-L2. Do not overwrite player location based on the ship.
4. Confirm owner intent for remote gateway selection, Terra route availability, paused timeout/resolution and zero saved remaining on resume.
5. Inspect external ShipArrival consumer idempotency and ordering, then exercise actual simultaneous departures/processor races and broker-after-send-before-commit crashes in isolation. These scenarios were not executed by this discovery.

Discovery is complete to the report's evidence boundary: a proven zero writer/survival mechanism, tested overlap with paused jump rejection, multiple independently proven local jump failures, an actionable prevention/recovery design, and a precise missing production request trace. **Implementation, player recovery, schema enforcement and deployment remain future scoped work.**
