# StarTrader jump travel and interdiction repair playbook

Prepared November 1, 2026. This is an executable Codex project specification, based on the supplied jump and travel discovery. Save it as `docs/STARTRADER_JUMP_TRAVEL_REPAIR_PLAYBOOK.md` in the StarTrader repository.

## Execution instruction

Read this entire playbook, the repository instructions, and `docs/STARTRADER_JUMP_TRAVEL_DISCOVERY.md` if present. Implement milestones M0 through M7 in dependency order. This authorizes the local implementation, tests, local schema rehearsals, documentation, and release preparation described below. Continue through routine milestones without requesting approval between them. Finish each milestone's acceptance checks before proceeding; record unresolved external dependencies without blocking independent work.

Production remains read-only during this execution. Prepare a concrete release and any necessary recovery manifest, then report the exact remaining operational actions. M8 describes a later production operation and must not run unless the owner explicitly authorizes that operation. Do not deploy, push to a deployment remote, run production migrations, resume ships, or alter player data merely because this document contains those later steps.

Maintain `docs/STARTRADER_JUMP_TRAVEL_REPAIR_STATUS.md` with the current milestone, implementation decisions, actual test results, changed files, unresolved items, and next action. Preserve unrelated working-tree changes. Follow repository branching and commit conventions; do not reset the checkout, overwrite someone else's work, or assume the discovery branch is still current. When a session ends, leave a precise continuation entry. A subsequent session should inspect the current code and status, then continue the first incomplete milestone.

## Corrected diagnosis and project decisions

The owner's correction supersedes the discovery report wherever they conflict:

> An interdicted ship may legitimately have `arrival_tick = 0`. The defect is not the existence of that sentinel. The system must distinguish intentional interdiction from invalid travel, show that distinction clearly, and prevent genuinely inconsistent travel from being created or silently discarded.

**Keep the current zero sentinel for interdiction in this project.** The implementation already has explicit `is_paused` and saved remaining-duration fields, and prior tests intentionally preserve zero. Migrating every paused journey to a positive arrival or introducing a new persisted enum would add compatibility work without solving the independent jump failures. Derive a clear display/diagnostic state from existing authoritative fields instead. A future representation change needs its own migration rationale; it is not required here.

In particular, do not apply the discovery's blanket `CHECK (arrival_tick > 0)`, backfill valid interdicted rows to fabricated deadlines, or change valid sentinel tests to assert positivity. Replace those recommendations with the conditional rules below. Preserve the discovery as historical evidence and record this correction in the implementation status and release notes.

Use these implementation defaults rather than stopping for routine design questions:

| Decision | Required default |
| --- | --- |
| Remote gateway selection | Preserve the existing tested behavior: an eligible co-located ship and player may select an origin gateway in their current system from another local station/location. Move their departure location consistently and atomically. Do not add an ordinary approach leg or new travel time. |
| Player location guard | Keep the arrival guard that avoids moving a player who legitimately moved elsewhere. Repair departure alignment and stale in-memory reads; never bypass the guard globally. |
| Interdicted ship requesting a new journey | Remain blocked until the existing interdiction is resolved through supported lifecycle rules. Return an accurate, actionable interdiction error. Do not silently resume, cancel, or abandon the journey. |
| Resume with zero saved remaining ticks | Preserve the current minimum-one-tick behavior unless current repository evidence establishes a different supported rule. Missing or negative remaining values are invalid; do not coerce missing data into a valid resume. |
| Stanton to Terra | Report the route as unavailable when no reciprocal gateway exists. Do not invent a destination gateway or edit the catalog to make a test pass. |
| Existing eight zero-arrival journeys | Preserve them if a fresh audit still confirms valid interdiction. No timing backfill or gameplay recovery is required just to eliminate zeroes. |
| New game mechanics | Retain existing timing, interdiction eligibility/windows, asset handling, broker routing, and authorization. This is a correctness and visibility project. |

## Evidence baseline and limits

These are findings from the supplied discovery, not assertions that the current checkout or runtime has already been reverified:

- Discovery checkout: `/home/dusti/startrader`, branch `codex/terminal-filter-production`, commit `e393c2834d774169a8e4541a084668b811a6e1c4`; origin `https://github.com/Seggellion/startrader.git`.
- Discovery runtime: Heroku app `star-trader`, domain `startrader.altama.energy`, release v171 at source `4d2d7cb97bea19f629a8f71262eaabf10748ebb8`. Relevant inspected travel source matched the later checkout. Verify identities and versions afresh before operational work.
- Stack: Ruby 3.2.2, Rails 8.0.1, PostgreSQL, Minitest, Delayed Job, RabbitMQ. Discovery used isolated PostgreSQL 18 while production was PostgreSQL 16.14; keep deployed-version compatibility in mind.
- Snapshot: eight zero-arrival rows, all paused, unfinished ordinary journeys, all ships marked interdicted, with coherent saved remaining time. No duplicate incomplete journeys, orphaned references, or positive overdue journeys were observed. Those counts are historical snapshots, not acceptance targets for today's runtime.
- Known travel IDs: `4607, 5007, 5028, 5042, 5043, 5071, 5090, 5121`. Six ships had cargo. All saved broker routes were `dev`; this does not make them disposable test data.
- Travel `5071` had a player-location discrepancy: ship/travel origin HUR-L2 Faithful Dream, player payload HUR-L1 Green Glade. Keep it paused and flag the discrepancy; do not teleport the player or authorize a resume by inference.
- Local reproductions established: remote-gateway departure can leave the player behind; lazy completion can reject one request using a stale player object; a paused journey blocks another jump; an unpaused zero can slip through availability checks; ordinary departure can commit only part of its state; broker failure followed by stale cleanup can delete an uncompleted journey.
- No real failed-jump request was correlated with a reporting player. Do not claim every production jump report is explained, or that fixing locally reproduced branches establishes a production incident's exact cause.

Useful source anchors from discovery, to revalidate in M0:

| Area | Files and symbols |
| --- | --- |
| Jump entry and location resolution | `app/controllers/api/gate_travel_controller.rb`, `app/services/gate_travel_service.rb`, `app/services/location_resolver.rb` |
| Availability and lazy completion | `app/services/ship_availability.rb`, `app/models/user_ship.rb`, `app/models/shard_user.rb` |
| Pause, resume, cancellation, cleanup | `app/models/ship_travel.rb`, `app/controllers/api/ship_travel_controller.rb`, `app/models/tick.rb` |
| Ordinary departure and timing | `app/services/travel_service.rb`, `app/services/travel_time_calculator.rb`, `lib/travel_timing.rb` |
| Arrival and publication | `app/jobs/ship_arrival_job.rb`, `app/services/ship_travel_arrival_processor.rb`, existing broker helpers/jobs |
| Status consumers | `app/services/trade_service.rb`, `app/controllers/locations_controller.rb`, relevant API payload builders |
| Admin presentation | `app/controllers/admin/ship_travels_controller.rb`, actual ship-travel and ship views, route helpers, existing authorization |
| Evidence and tests | `docs/discovery/jump_travel_discovery_test.rb`, `docs/discovery/read_only_travel_audit.rb`, `docs/discovery/jump_travel_runtime_sanitized.json`, existing gateway, model, job, and timing pipeline tests |

Missing supplementary discovery files are not a reason to abandon implementation: reconstruct focused synthetic regressions from this specification and current source. Do not fabricate the historical evidence they would have contained.

## State and timing contract

Treat pause state and timing as separate concepts. An arrival deadline determines when an unpaused journey is due; it does not determine whether an interdiction has ended.

| Persisted condition | Interpretation and behavior |
| --- | --- |
| No unfinished journey | Evaluate normal availability and authoritative location checks. A contradictory ship status is a separate diagnostic issue. |
| Unfinished, unpaused, positive arrival in the future | Scheduled travel; block another departure. Show remaining ticks. |
| Unfinished, unpaused, positive arrival due now or earlier | Due travel pending completion or retry; retain it until completion succeeds. Block a new departure unless safe lazy completion finishes first. |
| Unfinished, paused, zero arrival, coherent pause metadata | Intentional paused travel. Under the current interdiction writer this is valid interdiction; no automatic arrival and no scheduled ETA. Block another departure. |
| Unfinished, paused, positive arrival | Preserve the pause and inspect compatibility/history. A positive deadline must not cause a paused journey to arrive. Do not create a migration just to normalize an otherwise coherent legacy representation. |
| Unfinished, unpaused, zero arrival | Invalid travel. Fail closed on new departure, preserve evidence, and flag for review. Never ignore it and create a second journey. |
| Negative arrival, missing required timing, contradictory pause metadata, or duplicate unfinished journeys | Invalid or inconsistent state requiring explicit diagnosis; do not delete, invent a deadline, or automatically overwrite player location. |

For a legitimate paused-zero row, require an unfinished journey, an explicit paused flag, a saved pause tick and nonnegative remaining duration, and coherent interdiction metadata according to the real schema and supported writer. Zero alone is never sufficient to label a ship interdicted. Distinguish a valid pause from secondary inconsistencies such as a ship-status or player-location mismatch. Enforce cross-table consistency in lifecycle transactions and diagnostics, not a CHECK that tries to query another table.

Current formulas must remain:

- Ordinary duration: `max(ceil(distance_Gm / 1.0), 2)` ticks.
- Gateway duration: `ceil(120 / seconds_per_tick)` ticks; eight ticks at 15 seconds, four at 30 seconds.
- New departure: capture one authoritative tick, then `arrival = departure + duration` with valid positive duration and checked integer range.
- Interdiction: save remaining ticks and pause metadata, set the sentinel and interdicted state atomically; leave assets, destination and broker unchanged.
- Resume: use saved remaining duration at the actual resume tick, preserve established minimum-one-tick behavior, and update travel/ship state atomically. Do not recompute old journeys from today's orbit geometry.

Use the global persisted tick. Do not mix absolute ticks with relative durations, use orbital simulation seconds as scheduler seconds, change the 1 Gm/tick rate, change gateway timing, or promise exact wall-clock completion. Tick cadence is nominal and can be delayed.

## M0 Revalidate the baseline and establish regression cases

Read applicable `AGENTS.md` and project tooling instructions. Verify branch, HEAD, working tree, framework, actual test profile, and the cited code paths. The discovery used WSL Ubuntu from Windows; use that route if the current environment requires it rather than treating its UNC process failure as an application defect. Follow Chrome-only browser instructions if they still apply.

Verify the test connection is an isolated nonproduction database before booting Rails tasks or running schema/test preparation. Do not fall back to production credentials. The discovery's known working pattern was:

```sh
CODEX_ENV_FILE=.env.terminal-test bin/codex_test \
  test/controllers/api/gate_travel_controller_test.rb \
  test/models/ship_travel_test.rb \
  test/jobs/ship_arrival_job_test.rb \
  test/services/travel_timing_pipeline_test.rb
```

Confirm the profile still exists and is safe; never print its credentials. Keep `TICK_BOOTSTRAP=false`, use the existing fake broker/no-real-broker test protection, and control ticks without wall-clock sleeps. Historical baseline results were 52 runs / 954 assertions plus the separate discovery harness; rerun and report current results instead of quoting them as this execution's tests.

Convert defect characterizations into desired-behavior regressions in the normal test tree. Preserve tests for intentional interdiction zeroes. Establish the lock-order inventory across ordinary/gate departure, pause/resume/cancel, lazy completion, background arrival, status correction, and any supported admin lifecycle action.

**Acceptance:** a recorded baseline, current source map, corrected state contract, reproducible defects, and the smallest relevant test plan. Missing incident capture or external UI access is an explicit evidence gap, not a reason to stop local repairs.

## M1 Stop destructive loss of due journeys

Address the confirmed data-loss path first. An unpaused unfinished due journey is pending work, even after a processing error; it is not stale garbage.

- Remove or narrow automatic cleanup so it cannot delete incomplete due journeys or make their ships appear free. Audit callers of the cleanup scope and method, including tick side effects and status correction.
- Preserve a failed arrival for retry. Isolate per-journey failures so one bad destination or broker does not abort the entire batch or indefinitely starve other journeys. Use bounded, deterministic processing and observable failures.
- Keep paused journeys excluded from arrival regardless of arrival value. Make status consumers consistently recognize due-but-incomplete travel as pending work, not idle availability.
- Preserve due-now and missed-positive-deadline completion using `<=` semantics.

**Acceptance:** an injected broker failure through the actual tick/arrival path cannot delete an unfinished journey, fabricate arrival, or release the ship for a new departure. A later successful retry completes it once in authoritative database state. Another eligible journey can progress despite a failing row. A long-paused zero remains paused and present. Assets and saved broker remain unchanged.

M3 will separate publication from arrival; M1's intermediate failure test may evolve when the outbox is introduced, but the no-loss guarantee must continue passing.

## M2 Repair jump location handling and make lifecycle transitions atomic

Implement the narrow fixes and the shared concurrency boundary together:

1. Preserve remote gateway selection. First establish that ship and player are legitimately co-located in the current system. When selecting another origin gateway there, align both departure locations in the same transaction as travel creation and ship status. Do not use this alignment to conceal a preexisting player/ship mismatch.
2. After lazy completion, reload the authoritative ship and player, clear relevant association caches, then re-evaluate availability in the same request. A due arrival followed by a valid departure should not require a second request.
3. Keep arrival's conditional player-update guard. Test the case where the player legitimately moved elsewhere while the ship travelled; the player's location must not be overwritten simply to make a later request succeed.
4. Apply one documented lock order and transaction boundary to every competing lifecycle path. A suitable starting order is ship rows, shard-user rows, journey rows, then lifecycle receipt/event rows, each in stable ID order. Revalidate it against actual tick and processor nesting before adopting it. Do not leave the old arrival path locking a journey first while departure locks the ship first.
5. Under those locks, re-read the authoritative unfinished journey before creating another. Paused, invalid-zero, and failed-overdue journeys all block overlapping departures. Refresh associations after transitions.
6. Ordinary departure must roll back the journey and all ship/player updates together if any save fails. Apply the same atomicity to gate departure, interdiction, resume, and supported cancellation. Preserve existing interdiction eligibility and cancellation rules; do not add mass recovery actions.
7. Return stable, structured error categories for interdiction, invalid state, location mismatch, unavailable route, request conflict, and internal failure. Preserve existing HTTP/status/message conventions unless current consumers and tests justify a compatible change; add a code rather than silently breaking the response contract. Preserve authentication behavior and avoid exposing exception details or secrets.

**Acceptance:** station → remote gateway departure → arrival → next/return jump succeeds with initialized player location. Same-request lazy completion and departure succeeds. A preexisting mismatch remains a clear rejection with no writes. Genuine paused travel produces an interdiction message, not generic transit wording. An unpaused zero blocks another journey. Failure injection at each lifecycle boundary leaves no partial write. Real independent database connections demonstrate competing starts and pause/resume/arrival races obey the state contract and do not deadlock in tested schedules.

## M3 Add durable completion and request idempotency

Arrival database changes and RabbitMQ delivery cannot be committed atomically as one transaction. Move to a durable outbox, or a demonstrated equivalent with the same crash guarantees, using existing project infrastructure where suitable.

- In one database transaction, finalize authoritative ship/player state, record durable completion identity, and create a uniquely identified pending arrival event. Preserve existing travel deletion behavior if required by consumers, but retain the receipt/event evidence needed after deletion.
- Publish after commit through a retrying job. Persist the intended broker from the original journey and maintain the existing external payload contract. Never switch saved `dev` routing to production because the database is production.
- Preserve pending delivery on failure. Use stable event identity and prevent two dispatcher jobs from claiming the same event concurrently without recovery. Retain enough state to recover an interrupted claim.
- Test crash boundaries: before database commit, after commit before enqueue/send, after send before acknowledgement/mark-sent, and during dispatcher retry. A pending outbox event must be discoverable even if the enqueue callback is lost.
- Do not claim exactly-once external delivery. After an uncertain send, at-least-once delivery can duplicate a message; document the consumer's deduplication key and behavior if inspectable. If the external consumer cannot be inspected, identify that limitation in rollout readiness while completing the server-side protection.
- Make `travel_guid` request replay durable across arrival and row deletion. The same authenticated ship, normalized destination, kind, and immutable request context must not create a second journey. A conflicting reuse must fail clearly without exposing another ship's details. Respect the actual GUID uniqueness contract.
- Retain replay evidence across the client retry window. Do not invent a short receipt-expiry period that re-enables an old request to create another journey; document retention using existing integration contracts or preserve receipts for this release.

**Acceptance:** duplicate concurrent requests with one GUID produce one departure; different GUIDs for one ship produce at most one unfinished journey; conflicting GUID reuse is rejected. Replay after completion cannot create a fresh trip. Arrival commits once and remains correct through broker outages. Outbox work survives commit/enqueue/send crashes, uses the saved broker, and retries without duplicating authoritative completion or asset effects. Delivery duplication limits and consumer dependencies are stated accurately.

## M4 Make interdiction and invalid state clear in admin and status APIs

Use a shared state presenter/classifier so admin screens, normal status payloads, and diagnostic tooling agree. Avoid adding a second persisted travel-state column unless an evidenced requirement makes it necessary.

Admin travel index/show and relevant ship views must:

- Include all unfinished journeys, including paused and overdue ones. An `active` scope that excludes pauses is insufficient for diagnostics.
- Provide filters for all unfinished, scheduled, interdicted/paused, overdue/pending completion, and needs review. Review warnings may overlap a valid primary state.
- Display a clear primary state in text. Do not rely only on color. Show `Interdicted` for a supported interdiction, `Awaiting completion` for an overdue unpaused journey, and `Invalid travel state` for an unpaused zero or contradictory timing.
- For legitimate interdiction, replace the main raw zero/ETA with **No scheduled arrival while interdicted**. Show saved remaining ticks and a nominal time estimate explicitly qualified as time after resume. For example, 40 ticks at 15 seconds is approximately 10 minutes after resume. Put raw fields, including the zero sentinel, in diagnostic details.
- Show origin, destination, ship location, player location where authorized, pause tick, saved remaining duration, interdiction count/history fields that actually exist, travel kind, and saved broker. Flag a player-location discrepancy without overwriting it. A paused journey with a mismatch remains visibly paused and also needs review.
- Expose usable links to authorized ship/player/travel pages and avoid N+1 query regressions or an unbounded diagnostic scan per row. Retain existing admin permissions and escaping.
- Do not turn the copied/broken generic admin strong parameters into unrestricted raw timing/status editing. Keep new diagnostics read-only. Do not add Force Arrival, Resume All, or destructive cleanup controls.

Align in-repository location/travel/status consumers so an interdicted ship does not appear idle merely because `active_travel` excludes paused rows. Preserve raw API fields required by existing clients, adding compatible display state, pause reason, remaining duration, or warning fields where justified. There was no in-repository jump-button implementation in discovery; do not fabricate an external UI fix.

**Acceptance:** focused controller/view tests and, where supported, Chrome visual verification cover scheduled, valid paused-zero, paused with player mismatch, overdue retry, invalid-zero, and no-journey cases. Legitimate zeroes are not shown as overdue, arrived, or corrupt. The eight historical rows would classify as interdicted, with row 5071 additionally flagged for review. Admin/status rendering does not mutate journeys or player state. No automatic resume occurs on viewing a page.

## M5 Enforce conditional invariants and prepare targeted audit tools

After validating writers and state transitions, implement database protection appropriate to the actual data:

1. Keep arrival non-null and reject negatives. Permit zero **only** for an unfinished explicitly paused journey with the necessary non-null, nonnegative pause/remaining metadata and any other proven row-local interdiction requirements. Permit coherent positive paused legacy rows to remain paused. Check the actual column names, defaults, and nullability before drafting SQL.
2. Ensure the SQL condition cannot pass invalid state through PostgreSQL CHECK's NULL/unknown behavior. Use explicit null checks or justified NOT NULL constraints, and verify direct SQL bypass attempts. Cross-table ship status and player location remain application/diagnostic responsibilities.
3. Enforce at most one unfinished journey per ship, including paused rows, using an appropriate partial unique index after a fresh duplicate audit. Do not delete conflicts for index convenience. Keep existing GUID uniqueness and add necessary receipt/outbox uniqueness.
4. Do not globally impose historical duration or arrival-after-departure arithmetic that has not been audited. Validate exact formulas for new departures/resumes in supported writers.
5. Rehearse migrations and their operational sequence on representative synthetic legacy states. A NOT VALID CHECK still constrains new/updated rows, so it is not a blanket exemption for old invalid updates. Plan concurrent-index failure/retry handling and actual PostgreSQL 16 compatibility where relevant.

Provide a read-only audit that defaults to dry-run and separates: valid interdictions, ordinary pending travel, overdue retries, unpaused zeroes, malformed pause metadata, duplicate unfinished journeys, ship-status discrepancies, player-location discrepancies, and pending/failed notifications. Sanitized output should show evidence and proposed action; raw restricted output must not be committed or broadly shared.

For valid interdictions, the proposed action is **no gameplay or timing change**. For genuinely invalid rows, generate a per-record recovery proposal only when historical timing or authoritative completion evidence supports it. Where this scope needs an application tool, make it explicit opt-in, consume a reviewed manifest with expected before-state, and use the same lifecycle locks and an idempotent audit ledger. Re-read under lock and skip changed/uncertain rows. No direct blanket SQL repair, `current_tick + 1`, bulk deletion, inferred refund, or player teleport.

**Acceptance:** direct-SQL tests accept a coherent paused-zero and reject unpaused-zero, malformed paused-zero, negative/null arrival, and a second unfinished journey. Valid historical paused-zero rows need no rewrite to pass the new constraint. Positive paused compatibility is tested. Fresh audit distinguishes no-action valid interdiction from true invalidity. Any optional recovery tool is tested entirely locally for dry-run, stale manifest, idempotency, asset preservation, and refusal of ambiguous player state.

## M6 Qualify the complete lifecycle

Run the relevant model, service, controller, job, view, migration, and timing pipeline suites, then required repository checks and an appropriate integration/full suite. Do not count defect-characterization assertions as successful regression proof. Exercise real test PostgreSQL transactions/connections for concurrency and fake broker transport for external failures.

The final evidence matrix must cover:

| Scenario | Required outcome |
| --- | --- |
| Ordinary timing and tick zero | 1 Gm/tick, minimum two ticks; valid positive initial deadline |
| Gateway timing at 15 and 30 seconds | Eight and four ticks respectively; no ordinary-distance substitution |
| Remote gateway with initialized co-located player | Coherent departure and arrival; second jump works |
| Due/overdue arrival inside next request | No stale-player rejection; new journey only after successful completion |
| Player legitimately elsewhere at arrival | Guard preserved; no player teleport; understandable subsequent mismatch |
| Interdict and repeated interdict | Valid paused-zero, saved remaining unchanged by duplicate pause, no automatic arrival |
| Resume with positive/zero/missing/negative remaining | Existing positive and minimum-one behavior preserved; missing/negative refused safely |
| Valid pause after many ticks and app restart | Still paused, clear admin state, no cleanup or new departure |
| Unpaused-zero and malformed pause | Fail closed; review diagnostic; no second journey or deletion |
| Simultaneous ordinary/gate starts, same/different GUID | Atomic single unfinished journey; deterministic replay/conflict |
| Pause/resume/cancel versus arrival | Consistent locks and legal final state; no resurrected/deleted wrong journey |
| Save failure within departure or pause/resume | Complete transaction rollback; no split ship/travel/player state |
| Broker outage, crash boundaries, two dispatchers | Durable completion/event; retryable delivery; documented dedup limits |
| Missing Terra reciprocal and ambiguous gateways | Explicit rejection without writes or invented catalog data |
| Admin rendering and status endpoints | Pause is visible, diagnostics read-only, raw compatibility retained |
| Conditional constraints and migration rehearsal | Valid sentinel accepted; invalid writes/duplicates rejected without data loss |

Measure cargo rows/quantities, SCU, wallets/inventory, destination, and broker before/after the relevant tests. Do not introduce a resource debit or refund that the existing services do not perform. Use meaningful asset assertions, not just row-count smoke tests.

If browser execution is unavailable, provide rendering/controller evidence and state exactly which visual checks remain. If external client/consumer access is unavailable, separate server qualification from that missing acceptance; do not call it end-to-end verified.

**Acceptance:** required checks pass with recorded commands and outcomes, or a concrete blocker is documented with completed independent work. No unresolved data-loss regression may be waived to mark the release ready.

## M7 Prepare the release and finish the local execution

Write `docs/STARTRADER_JUMP_TRAVEL_REPAIR_RELEASE.md` containing:

- The final code changes and corrected interdiction policy, with exact source revision or working-tree provenance.
- Actual test results, migration rehearsal results, Chrome/admin evidence, and explicit unverified external dependencies.
- Ordered schema/application/worker rollout steps, compatibility of old/new writers, migration lock and index strategy, and outbox dispatcher/recovery scheduling. Include a deployable ordering that never starts code against missing required tables or columns.
- A fresh read-only audit procedure, relevant health/error queries, and operational stop conditions. Track invalid zeroes separately from valid paused zeroes; a healthy system may retain interdicted rows indefinitely under current rules.
- A per-record manifest only if true invalid state needs an operational action. Keep valid interdictions as no action. List row 5071 or its current equivalent as a player-location review, not an approved gameplay mutation.
- Rollback boundaries, including schema compatibility and the fact that already published events or later player actions cannot be undone by restoring a journey row. Prefer roll-forward for irreversible effects.
- The exact remaining production actions and whether any require an owner gameplay decision, external consumer change, or additional authorization.

Complete the status file and final implementation summary. Do not stop after writing another plan: by the end of M7, all authorized local implementation and qualification must have been performed. Do not claim production is fixed when only local changes are ready. If the same session explicitly authorizes a named production operation, proceed within that scope using M8; otherwise stop at this prepared result.

## M8 Later authorized rollout and observation

This milestone is operational guidance, not permission to perform production changes. When explicitly authorized:

1. Reverify app/domain/database identity, deployed revision, reviewed candidate revision, fresh audit, backup availability, and the exact schema/application/worker ordering from M7. Do not reuse a historical eight-row list as an unconditional mutation target.
2. Apply the reviewed compatible rollout. Validate constraints/indexes only when the rehearsed preconditions hold. Preserve paused-zero writers that conform to the corrected invariant.
3. Perform any separately authorized true-invalid-state recovery by reviewed manifest, first as a canary and then bounded batches. Require expected state and an atomic audit ledger under lifecycle locks. Preserve assets and original broker routing. Skip changed rows; do not resume a valid interdiction as housekeeping.
4. Observe bounded counts for invalid-zero/malformed/duplicate journeys, overdue retries, arrival failures, pending/failed outbox events, worker health, and normal gateway errors. Report valid paused journeys separately.
5. Verify admin labeling and capture a real failed-request trace when available: timestamp, endpoint, sanitized payload, response, gateway selection, ship/player/travel state, and deployed revision. Do not trigger real player travel just to obtain evidence without authorization.
6. Stop on unexplained asset/location changes, lost journeys, duplicate lifecycle effects, identity drift, incompatible consumer behavior, migration/lock problems, or rising unprocessed events. Use the reviewed rollback or roll-forward plan; never restore old rows blindly after gameplay or publication.

Production closure requires the deployed fixes and conditional guards to be verified, no unexplained lost arrivals, accurate paused/admin visibility, and an explicit disposition for outstanding anomalies. It does **not** require zero interdicted ships, zero sentinel values, a fabricated Terra route, or forced movement of paused players.

## Copyable kickoff for Codex

```text
Read docs/STARTRADER_JUMP_TRAVEL_REPAIR_PLAYBOOK.md completely and execute M0 through M7. Follow repository instructions and preserve unrelated changes. The owner's updated rule is authoritative: arrival_tick=0 is valid for coherent interdicted/paused travel; do not apply blanket positivity or backfill legitimate interdictions. Preserve tested remote gateway selection, repair atomic ship/player location handling and lazy completion, stop destructive cleanup, add durable completion/delivery and replay protection, and make admin/status views distinguish interdiction from invalid travel. Reverify findings against current source, use isolated PostgreSQL and fake brokers, and finish the regression, concurrency, migration, and release-preparation work. Update docs/STARTRADER_JUMP_TRAVEL_REPAIR_STATUS.md as you go. Continue across routine milestones without reapproval. Production is read-only unless I explicitly authorize a named M8 operation. Finish with implemented changes, actual test results, remaining external dependencies, and the concrete release steps still awaiting execution.
```
