# StarTrader jump travel repair status

**M0–M8 complete. Production v172 is deployed and verified.**
Deployed source:b82472163ff6b73abc6d37323dacd3665b027087.
Branch:codex/jump-travel-repair. Implementation baseline:e393c2834d774169a8e4541a084668b811a6e1c4.
A documentation-only closeout commit follows the deployed source; no second deployment is needed.
Production evidence:[M8 record](discovery/jump_travel_m8_production.json).
Unrelated initial untracked files remain preserved.

## Authoritative policy

The repair playbook corrects the historical discovery:arrival_tick=0 is valid for coherent unfinished interdiction. Keep the sentinel; no blanket positivity, fabricated deadline or timing backfill. Ordinary1Gm/tick/minimum2 and gatewayceil(120/seconds_per_tick) are unchanged.

## Milestone acceptance

| Milestone | Completed implementation / evidence |
| --- | --- |
| M0 |Branch/state/source/tooling reverified; loopback profiles checked before Rails; original52/954 focused baseline passes; Chrome-only testing. |
| M1 |Incomplete due journeys retained; per-record failures isolated; pending ships not released. Intermediate35/879 passes. Final outbox contract commits completion independently of broker health. |
| M2 |Atomic ship/player departure alignment, fresh lazy completion, retained player-origin guard, all unfinished/invalid states block overlaps; atomic pause/resume/cancel and supported ship destruction locks. Independent PostgreSQL backend races pass. |
| M3 |Durable GUID receipts without expiry; after-deletion replay and conflict protection; legacy identity reserved when known; durable completion/outbox; after-commit delivery/timed retries; lost-enqueue sweep, SKIP LOCKED crash-recoverable claims, confirms with bounded wait, stable identities. All crash boundaries tested synthetically. |
| M4 |Shared pure classifier and presenter; authenticated read-only bounded/eager admin filters/details and ship/player views; compatible status fields;0 scheduled ETA for valid interdiction replaced with explicit no-arrival label and time-after-resume. Six Chrome states pass. |
| M5 |Conditional CHECK (NOT VALID then validation), concurrent unfinished-per-ship uniqueness, receipt/event uniqueness; direct-SQL bypass and PostgreSQL16 down/up/invalid-index/refusal rehearsals pass. Standalone sanitized read-only audit; no invalid-state mutation tool needed. |
| M6 |Final focused:177/1633 passes. Candidate full:523/5695,33 failures/25 errors exactly matching58 fresh baseline identities;0 new. Tailwind, Zeitwerk and diff checks pass. |
| M7 |[Release document](STARTRADER_JUMP_TRAVEL_REPAIR_RELEASE.md), exact-source manifest, qualification/regression evidence, corrected fresh audit, Chrome captures, ordered rollout, rollback limits and continuation prepared. |

## Final implementation decisions

Lock order:ship→shard-user→GUID advisory→journey→receipt/event. Subset paths never acquire a later GUID after a journey; absent new GUIDs are not held during lazy completion of an older identity. Tick commits economy before arrival. Ship destruction locks the parent before dependent journey deletion; explicit existing destruction rules remain.
Request context is normalized and bound to ship/kind/destination/broker as appropriate. Known legacy GUIDs without reconstructable request context are refused as fresh requests; already-deleted pre-release journeys without history cannot acquire retroactive replay evidence.
Interdiction/resume are atomic; zero saved remaining keeps minimum-one resume; missing/negative metadata is refused. Positive paused legacy state remains paused. No mass recovery action.
Delivery is at least once. Event GUID/message_id plus travel GUID remain stable; the original pipe payload is preserved and auth secret is not stored in outbox. Publisher confirm wait bounded15sec, timeout closes channel and preserves retry; broker connection uses existing configuration. A broker outage cannot undo committed location/completion. Consumer deduplication is not verified.

## Test environments and final evidence

- PostgreSQL18:existing limited local profile .env.terminal-test,star_trader_terminal_test on loopback5432.
- PostgreSQL16:disposable user-owned UTF-8 cluster,port55437,star_trader_repair16_test. Earlier port55436 SQL-ASCII template caused a Rails scratch-database recreation failure after schema dump; reinitialized UTF-8 and reran successfully. This was a local harness correction.
- Both:TICK_BOOTSTRAP=false,single worker,synthetic data,no real broker connections,no wall sleeps.
- Chrome:explicit installed Google Chrome via retained test/browser/jump_travel_admin_chrome.py;6 synthetic authenticated HTML snapshot states, scripts removed/local built CSS inlined. Interdicted/invalid screenshots inspected. This is visual rendering evidence,not external-client end-to-end qualification.
- Full untouched base exported via git archive into ignored tmp/jump-repair-baseline-source; separate PG16 database. No unrelated baseline failures were hidden by extra application repairs.
- Exact commands, counters and retained failures:release document and docs/discovery/jump_travel_repair_regressions.json.

## Runtime audit and no-action manifest

Fresh read-only identity:v171/source4d2d7cb97bea19f629a8f71262eaabf10748ebb8; expected Heroku app/domain/add-on binding and web/worker verified.
Latest audit UTC time and tick are in docs/discovery/jump_travel_repair_audit.json. Eight valid paused-zero interdictions,0 null/negative arrival,0 completed-zero,all saved brokerdev,six cargo-bearing ships.
IDs4607,5007,5028,5042,5043,5071,5090,5121 remain **no timing or gameplay action**.5071 adds player-location review; keep paused and do not teleport.
No true-invalid-state recovery manifest/applier is warranted. The sanitized audit is a no-action/review manifest,not a write authorization.

## Changed files

Runtime:TravelLifecycle/TravelState/TravelStateContract; both travel services; ShipAvailability; ShipTravel/UserShip/Tick; arrival processor/job; RabbitmqSender; new receipt/outbox models and dispatcher; API/status/locations consumers; read-only admin travel/ship/player views/routes.
Schema:20261101010000–20261101010300 and db/schema.rb.
Diagnostics:script/audit_travel_lifecycle.rb.
Tests:new lifecycle/concurrency/constraints/migration/admin fixtures and browser capture; existing affected tests updated for supported semantics and asynchronous delivery. Original discovery sentinel-preservation tests stay valid.
Documentation:requested playbook,status,release,source manifest,audit/identity,regression and Chrome evidence. Unrelated initial untracked files and historical discovery preserved.

## Continuation / next action

M8 was explicitly authorized and executed; the committed candidate is live asv172. Do not repeat the rollout as a continuation task. Follow the release's expand-tables-before-code,retire-old-writers,conditional-guards/validation ordering. No unrestricted migrations or old-slug rollback after receipts/events exist.
External prerequisites:consumer deduplication/acceptance of at-least-once delivery; external client request/error handling and a real incident trace; owner review of5071. These do not authorize player movement. Terra remains unavailable.
Disposable test databases/archives/logs and Chrome-only profiles remain ignored/local; private PostgreSQL16 servers are stopped at handoff. Recreate UTF-8 local cluster/profile to rerun; never fall back to production credentials.

## M8 authorization and execution log

Owner instruction: proceed with M8 using the release plan; commit/deploy repairs; apply conditional migrations and verify production; keep valid interdictions paused and5071 unchanged; remind the owner afterwards.
Preflight2026-11-01T16:04:48Z: v171 identity/binding verified; eight valid interdictions;5071 same discrepancy; no null/negative/completed-zero or orphan references.
Delivery boundary remains disclosed at-least-once with unverified external consumer deduplication. The owner's explicit proceed instruction authorizes rollout with that documented limit; no exactly-once external claim and no manufactured production message/jump.
Operator preparation adds a standalone ActiveRecord-only runner for the exact four reviewed migrations, database/SHA gates and protected-record fingerprints. No Rails application boot or broker/tick callbacks.
Executed: source commit/push, exact-SHA177/1630 qualification,5 operator rehearsals, backupb005, maintenance/quiescence, additive schema, v172 deployment, all conditional guards/validation, restored web/worker, reopened ingress and bounded production verification. No gameplay recovery performed.

## M8 final handoff

- Releasev172,sourceb82472163ff6b73abc6d37323dacd3665b027087; all four migration versions recorded; conditional CHECK validated and unique indexes ready/valid.
- Backupb005 Completed; original web/worker formation restored; app config fingerprint unchanged; no manual ticks or queue purge.
- All8 protected journeys remain paused withzero arrival; all protected travel/ship/player/cargo/user and timing-setting fingerprints unchanged through2026-11-01T16:49:33Z.
-5071 is unchanged and still flagged:shipHUR-L2 Faithful Dream Station versus playerHUR-L1 Green Glade Station. Keep paused; owner review only. Remind the owner in the final response.
- Production broker connected. Development broker TCP connectivity failed; the owner confirmed it is **intentionally offline—keep configuration**. No routing/configuration change.
- Tick/dispatcher healthy,failure_count0,failed queued jobs0,pending delivery0. No manufactured production journey or publication. External consumer deduplication/end-to-end notification delivery remains unverified because no natural arrivals occurred.
- Live HTTP/asset checks and Google Chrome health/render capture passed. Admin diagnostics were rendered internally against live read-only DB and role-checked operator context,not an authenticated HTTP browser session. Interactive browser tool initialization failed with MXC; fallback used only installed Google Chrome.
- No new production blocker or data recovery operation remains. Future work:normal observation,external consumer deduplication acceptance,and separately authorized5071 review. Do not resume or teleport it as cleanup.
- Code/source files match the qualified manifest. Remaining commit is documentation/evidence only. Original unrelated files remain untracked and untouched.
