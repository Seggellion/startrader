# StarTrader jump travel and interdiction repair release

Prepared 2026-11-01 UTC. **M0–M7 local implementation and release preparation; M8 has not run. Production is not fixed by this local delivery.**

## Corrected policy and provenance

The owner's repair playbook supersedes the discovery's proposed blanket positivity invariant. **arrival_tick=0 is valid for coherent unfinished interdiction.** Keep those journeys paused, with no scheduled arrival; do not backfill a deadline, resume, refund, cancel, delete or teleport as housekeeping. The discovery and its characterizations remain historical evidence.

Branch: `codex/jump-travel-repair`. Base/HEAD remains `e393c2834d774169a8e4541a084668b811a6e1c4`; implementation is **uncommitted working-tree content**, identified by [source manifest](discovery/jump_travel_repair_source_manifest.json). No commit, push or deployment performed. Review/commit a concrete candidate and record its exact SHA before an authorized rollout; compare its source hashes to this manifest and rerun qualification if content changes.

Unrelated initial untracked files were preserved: .claude/, both existing Zone.Identifier files and root STARTRADER_TERMINAL_FILTER_PLAYBOOK.md. The existing historical discovery/report evidence was retained.

Fresh read-only [production identity](discovery/jump_travel_repair_identity.json): v171, source `4d2d7cb97bea19f629a8f71262eaabf10748ebb8`, Heroku star-trader, expected domain/database add-on binding verified; web.1 and worker.1 up. That running revision does **not** contain this repair.

## Implemented behavior

- Incomplete due journeys are pending work. Stale cleanup removes completed historical rows only and never releases another unfinished journey. Status correction keeps a ship occupied while any unfinished journey exists. Batch arrival errors are isolated and logged by record id/error class.
- Both start services use atomic ship/player/journey writes. Remote gateway selection preserves the existing shortcut and travel time: validate original co-location, move ship and player to the chosen same-system origin together, and create travel in that transaction. A preexisting mismatch is rejected. Lazy completion reloads authoritative ship/player state in the same request.
- Arrival retains the origin-match player guard: a player who moved elsewhere is not teleported. Interdiction/resume/cancellation update journey/ship atomically and recheck under locks. Repeated valid interdiction preserves saved remaining time. Zero remaining resumes with the established one-tick minimum; missing/negative or contradictory metadata is refused.
- All unfinished travel, including invalid-zero and overdue, blocks overlapping departures unless safe lazy completion actually finishes. Errors add stable categories for interdiction, invalid state, location mismatch, unavailable route, request conflict and internal failure without exposing unexpected exception details.
- A durable travel_request_receipts row reserves each new request GUID indefinitely. Same ship/context replay returns the original pending/completed/cancelled outcome after journey deletion; conflicting reuse is refused without revealing another ship's details. Normalization covers case, whitespace and gateway parenthetical suffixes. Retention has **no expiry** in this release.
- A legacy still-present GUID without a receipt is reserved and refused as a new request: its original immutable context cannot be fabricated. Legacy completion/cancellation and cleanup of already-completed historical rows record a receipt with explicit legacy context, preventing later reuse. Deleted pre-release journeys with no historical ledger cannot retroactively gain replay evidence; guarantees for those lost historical identities cannot be proven.
- Completion atomically commits destination state, receipt and a uniquely identified outbox event, retaining journey deletion semantics. A broker outage now leaves **completed database arrival plus pending notification**, rather than holding the authoritative arrival open or losing it. Payload snapshot and saved broker survive later ship/player changes.
- Event creation enqueues TravelArrivalDispatchJob after commit on travel_notifications. A failed send records attempts, error class and backoff, then enqueues a timed retry after commit. A tick sweep independently discovers committed pending work if enqueue is lost. Each sweep is bounded to 100 due events, deterministic id order.
- Dispatcher claims use transaction-scoped event row locks with SKIP LOCKED. Process death releases the claim; no unrecoverable permanent claim flag exists. Publisher confirms are required; confirmation wait is capped at15 seconds, with channel closure and retry on timeout (Bunny2.24 otherwise polls indefinitely). In-process publication is serialized while confirming on the cached RabbitMQ channel.
- Existing pipe-delimited ShipArrival contract is retained, including original travel_guid in its final field and tagId/routing key behavior. The outbox stores payload fields **without** authentication secrets; current secret is inserted only at publication. Broker comes from the original journey, including dev journeys on the production database. Message properties add stable event_guid as message_id and travel_guid as a header.
- The shared pure TravelStateContract/TravelState classify scheduled, interdicted, awaiting completion and invalid states. Admin index/show/edit diagnostics are read-only, eager-loaded, bounded/keyset-paged and filtered by unfinished/scheduled/paused/due/review. Read-only admin routes retain login/admin authorization. Copied raw timing editing/destructive controls are disabled rather than expanded.
- Valid interdiction shows **No scheduled arrival while interdicted**, saved remaining ticks and nominal time **after resume**, with raw zero and metadata inside diagnostic details. Player/status discrepancies remain secondary warnings. Ship/player views and status/location payloads expose the same derived state while retaining raw client fields.
- Ordinary timing remains max(ceil(physical Gm / 1.0), 2); gateway timing remains ceil(120 / seconds_per_tick). Tick zero yields a positive initial deadline; integer range is checked. No approach leg, resource debit/refund, orbital, cooldown, range, authorization or catalog mechanic was added. Missing Terra reciprocal remains unavailable.

## Lock and crash contract

Order for participating locks: **ship → shard-user → GUID advisory lock → journey → receipt/event**; multi-row selections use stable id ordering. Supported ship destruction wraps dependent journey deletion in the same parent-first order. Pause/resume/status correction use subsets and never acquire a GUID after a journey. Tick commits tick/economy before entering arrival. Dispatcher takes event locks only and never calls back into ship/player/journey.

Absent fresh request identities are not advisory-locked before lazy completion; they are reserved/rechecked after existing arrival work. This prevents a new request lock from being held while waiting for a different legacy journey's identity. Existing receipt replays return under the owning ship/GUID lock. Independent-connection tests cover same/different GUID starts, ordinary/gate overlap, pause/resume/cancel versus arrival and two dispatchers.

Crash boundaries tested: rollback before completion commit; durable event when enqueue fails; independent sweep recovery; exception/process-death simulation after send before mark-sent; replay after journey deletion; retry with unchanged event identity. A real broker/consumer crash was not induced.

**External delivery is at least once, not exactly once.** A crash after a successful send before sent_at commits can resend the same event. Proposed consumer deduplication key is event_guid/message_id, with original travel_guid available in both payload and headers. No external consumer repository or live consumer behavior was inspected; its existing deduplication behavior is **unverified**. Do not infer exactly-once gameplay/notification effects. Operational acceptance must explicitly resolve/accept this boundary before M8; no consumer change was silently made.

## Conditional schema guards

Migrations, in order:

1. **20261101010000** CreateTravelLifecycleReceipts: additive receipt/outbox tables and uniqueness indexes.
2. **20261101010100** GuardTravelArrivalState: named NOT VALID CHECK `ship_travels_arrival_state`.
3. **20261101010200** GuardUnfinishedShipJourneys: partial unique index `index_one_unfinished_journey_per_ship` on user_ship_id WHERE completed_at_tick IS NULL, built CONCURRENTLY outside a DDL transaction.
4. **20261101010300** ValidateTravelArrivalState: validate the rehearsed CHECK.

The CHECK rejects null/negative arrival, and permits zero only when paused=true, incomplete, with non-null nonnegative departure/pause/remaining, pause >= departure, count >0 and matching non-null last-interdicted tick. Every nullable component has explicit null guards, avoiding PostgreSQL CHECK/UNKNOWN acceptance. Existing NOT NULL and GUID uniqueness remain. Coherent positive paused legacy rows remain paused and accepted. No global historical duration/arrival arithmetic or cross-table CHECK is imposed.

NOT VALID still constrains **new and updated** rows, including updates to old invalid rows. Do not use it as permission to update old invalid data without review. Cross-table status/player differences are handled transactionally and diagnostically. Existing duplicates cause the index migration to stop without deleting them; a failed concurrent build can leave an invalid index. The migration refuses that state with an explicit review/drop-concurrently/retry instruction. Inspect the exact index definition, uniqueness, predicate, readiness and validity; do not accept a same-named different index.

## Actual qualification

| Executed check | Actual final result |
| --- | --- |
| M0 original focused baseline |52 runs /954 assertions;0 failures/errors/skips |
| M1 intermediate no-loss suites |35 /879;0 failures/errors/skips |
| Final focused lifecycle/API/model/job/migration/admin/timing/broker suites on PostgreSQL16 |177 runs /1633 assertions;0 failures/errors/skips |
| Fresh untouched base full suite, separate PostgreSQL16 database |482 /5396;33 failures,25 errors,0 skips |
| Final candidate full suite on PostgreSQL18 |523 /5695;33 failures,25 errors,0 skips |
| Failure identity comparison |58 retained baseline identities;**0 new**,0 resolved |
| Chrome state capture |6/6 passing; no other browser used |
| Terminating Tailwind build |Passed; existing Browserslist warning |
| Zeitwerk eager-load check |Passed; existing test/mailers/previews exclusion noted |
| git diff --check |Passed |

The focused run includes real PostgreSQL transactions/independent backends and a real queued tick pipeline with fake broker transport. Its assertions do not count the discovery's old defect-characterization harness as regression proof. The candidate adds 41 test cases relative to the untouched base. The full suite remains **not green**; all58 failures/errors exactly reproduce at the base revision.

Commands (WSL repository root; profiles verified loopback/nonproduction before Rails preparation):

```sh
CODEX_ENV_FILE=.env.terminal-test bin/codex_test
# Full candidate suite on isolated PostgreSQL18.

CODEX_ENV_FILE=tmp/jump-repair-pg16.env bin/codex_test \
  test/services/travel_repair_lifecycle_test.rb \
  test/services/travel_repair_concurrency_test.rb \
  test/models/travel_constraints_test.rb \
  test/migrations/travel_schema_rehearsal_test.rb \
  test/controllers/admin/travel_diagnostics_test.rb \
  test/controllers/api/gate_travel_controller_test.rb \
  test/controllers/api/ship_travel_controller_test.rb \
  test/models/ship_travel_test.rb test/jobs/ship_arrival_job_test.rb \
  test/models/tick_test.rb test/services/travel_timing_pipeline_test.rb \
  test/services/travel_service_test.rb test/services/rabbitmq_sender_test.rb
```

PostgreSQL16 ran in a disposable user-owned cluster, loopback port55437 (final UTF-8 cluster; earlier rehearsals used55436), database star_trader_repair16_test; no production data imported. PostgreSQL18 used the existing limited local role/profile and star_trader_terminal_test. TICK_BOOTSTRAP=false, single test worker, synthetic fixtures, fixed ticks, no wall sleeps, no-real-broker protection and fake transport. The real queued timing pipeline continues to execute TickJob/Delayed::Worker, separately from tests that directly set synthetic due ticks.

Schema rehearsals actually exercised NOT VALID on preexisting invalid synthetic data (retained), rejection of subsequent invalid updates, failed validation, corrected synthetic fixture validation, valid paused-zero without rewrite, positive-paused compatibility, duplicate refusal, failed concurrent build leaving an invalid index, explicit local fixture disposition and successful retry. Production PostgreSQL16 compatibility was exercised on a real PostgreSQL16 server, not inferred from PostgreSQL18.

The fresh untouched base was exported with git archive HEAD to ignored tmp/jump-repair-baseline-source and run against a **separate** PostgreSQL16 database. Failure identities are compared in [regression evidence](discovery/jump_travel_repair_regressions.json); unrelated baseline admin-auth/routes/market/trading failures are not concealed with unrelated repairs. The full production-line suite is **not green**.

An initial SQL-ASCII template in the disposable PostgreSQL16 cluster prevented Rails from recreating a scratch database after a schema dump. That local harness issue was resolved with a fresh UTF-8 cluster; final checks passed there. No production configuration changed.

Terminating Rails tailwindcss:build passed. Existing caniuse-lite/Browserslist freshness warning remains; no dependency update was made for it. Authenticated controller/render tests exercise all states, raw compatibility, read-only behavior, access restrictions and no per-row SQL growth.

[Google Chrome evidence](discovery/jump_travel_repair_chrome.json): six synthetic authenticated Rails-rendered snapshots (no journey, scheduled, valid interdicted, paused with mismatch, overdue, invalid) captured using the explicit installed Google Chrome executable. Scripts/external stylesheets were removed and the built local Tailwind CSS inlined for **visual state verification only**. The interdicted/invalid images were visually inspected; no external jump client or browser end-to-end flow is claimed. Reusable capture command: python3 test/browser/jump_travel_admin_chrome.py --output-dir <absolute Windows evidence directory>, after TRAVEL_REPAIR_CAPTURE_HTML=true with the authenticated rendering tests. Native Node tooling could not start because of the host process-security error; Chrome capture succeeded through WSL with a separate headless profile. No other browser was launched.

## Fresh audit and recovery disposition

Use [script/audit_travel_lifecycle.rb](../script/audit_travel_lifecycle.rb), not the superseded discovery's positivity/recovery recommendations. It does not boot production Rails, contact brokers, or offer an apply mode. It uses read-only repeatable-read transactions, 10-second statement and 2-second lock timeouts; reports sanitized IDs/categories/counts and at most1000 records with explicit truncation/sample counts. Raw ship/player GUIDs, wallet values and secrets are omitted.

```sh
bin/codex_exec bundle exec ruby script/audit_travel_lifecycle.rb --heroku-app star-trader
# Or use an explicitly selected DATABASE_URL; never print the credential.
```

Latest [read-only audit](discovery/jump_travel_repair_audit.json) and identity evidence record their own exact UTC times. Eight unfinished journeys still classify as valid interdiction, arrival0, saved broker dev, six with cargo. IDs:4607,5007,5028,5042,5043,5071,5090,5121. **All remain no timing/gameplay action.** 5071 remains interdicted plus player-location discrepancy: review only, not an approved resume or teleport. No true-invalid-state recovery manifest/applier is warranted from this snapshot. The audit artifact is a per-record no-action/review disposition, not a mutation authorization.

If a later audit finds true invalidity, stop that scope, collect historical timing/authoritative completion evidence and obtain a reviewed per-record action manifest with expected before-state, assets, broker and idempotent recovery ledger under these lifecycle locks. There is intentionally no blanket SQL repair, current_tick+1 fallback, deletion/refund or automatic player relocation tool in this delivery.

## Concrete later rollout sequence — not executed

Every production step below is M8 and needs explicit operational authorization.

1. Review/commit the working-tree candidate, establish exact immutable SHA, match the source manifest, and confirm consumer deduplication or explicit acceptance of at-least-once delivery. Identify a compatible roll-forward/rollback build and operator/runtime. Do not deploy an unspecified branch head.
2. Freshly verify app/domain/add-on/database binding, running release/processes, migration history, candidate schema diff and corrected read-only audit. Snapshot/backup production and verify restore availability; record a targeted before-image of travel/ship/player/assets and pending notifications without publishing credentials.
3. In an approved maintenance window, stop ingress and gracefully quiesce old workers/in-flight travel requests. Record tick and jobs; **do not advance/reset ticks or purge queues**. This protects the shared-lock cutover from old journey-first workers and nontransactional writers.
4. **Before starting the new application/worker**, apply only additive migration20261101010000 from the reviewed candidate in an operator migration process with TICK_BOOTSTRAP=false and the exact authorized production connection. Candidate Rails can load model definitions for this one-off migration without serving traffic; do not start a server/worker against missing tables. Inspect other initializers and the actual release hook before execution; no unrestricted db:migrate or accidental unrelated migration.
5. Deploy the exact candidate with the additive tables present; verify all web/worker processes use that revision before reopening traffic. Workers must process **both default and travel_notifications** queues. The Procfile jobs:work processes all queues unless a production QUEUES restriction exists; audit that configuration read-only and explicitly adjust it only within M8 if needed.
6. Re-audit legacy states/duplicates. Apply20261101010100 (NOT VALID CHECK), then20261101010200 (CONCURRENT unique index, outside a transaction), then20261101010300 (validation), each as a named/version-scoped operation. Use short lock_timeout and bounded statement_timeout; a concurrent build needs enough execution time but must not wait indefinitely. Stop on invalid rows or duplicates, never delete them for migration convenience. All current eight valid interdictions need no rewrite.
7. Verify CHECK validated and full index definition/indisvalid/indisready, receipt/event uniqueness and unchanged asset/location/broker state. Do not remove additive tables or mark unvalidated constraints as completed. Resume normal ingress/worker/tick operation only with the verified compatible code/schema combination.
8. Observe pending/delayed/error event counts, actual callback/timed retries, tick sweep and worker health. Lost-enqueue fallback is the regular Tick→ShipArrivalJob→TravelArrivalDispatchJob sweep. If ticks are deliberately stopped, after-commit delivery/timed retries still run; also arrange an explicitly authorized periodic dispatcher sweep for recovery from a lost enqueue while ticks remain stopped. No schedule was created by this local execution.
9. Verify admin labels and additive status fields with Chrome and safe read-only requests. Capture a real failed client request if available; do not manufacture production player travel. No existing valid interdiction should move merely because a page or audit is viewed.
10. No data recovery operation is currently needed. Any future true-invalid-row recovery requires its own reviewed manifest/canary/batch authorization and ledger; do not treat this list of eight as unconditional targets.

Migration command shape for the approved operator environment:

```sh
# M8 ONLY, with exact authorized connection/runtime and TICK_BOOTSTRAP=false:
RAILS_ENV=production TICK_BOOTSTRAP=false bin/codex_exec bundle exec rails db:migrate:up VERSION=20261101010000
# Start reviewed application only after additive tables verified.
# Later, after old processes are retired and fresh audit passes:
# ... db:migrate:up VERSION=20261101010100
# ... db:migrate:up VERSION=20261101010200  # nontransactional concurrent index
# ... db:migrate:up VERSION=20261101010300
```

Do not copy/run these commands during the current read-only execution. A Heroku old slug does not contain the new migration files; use the reviewed candidate's prepared operator runtime/artifact, not an assumption that running old release migrations can expand the schema.

## Health queries and stop conditions

Read-only, proposed operator checks (not claimed executed against a deployed outbox):

```sql
SELECT conname,convalidated,pg_get_constraintdef(oid)
FROM pg_constraint WHERE conrelid='ship_travels'::regclass
AND conname='ship_travels_arrival_state';

SELECT c.relname,i.indisvalid,i.indisready,pg_get_indexdef(i.indexrelid)
FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
WHERE c.relname='index_one_unfinished_journey_per_ship';

SELECT count(*) FILTER(WHERE sent_at IS NULL) pending,
       count(*) FILTER(WHERE sent_at IS NULL AND last_error_class IS NOT NULL) retrying,
       min(created_at) FILTER(WHERE sent_at IS NULL) oldest_pending
FROM travel_arrival_events;

SELECT user_ship_id,count(*) FROM ship_travels
WHERE completed_at_tick IS NULL GROUP BY user_ship_id HAVING count(*)>1 LIMIT 20;
```

Use the shared corrected audit for valid interdictions vs invalid zeroes, malformed metadata, status/player discrepancies, duplicates, orphans and pending/retrying notifications. In logs monitor arrival_failed, lazy_arrival_failed, arrival_delivery_failed, arrival_dispatch_failed, arrival_enqueue_failed and arrival_retry_enqueue_failed by id/error class; no exception credentials should be logged.

Stop on identity/version drift, unsupported schema/queue configuration, invalid/duplicate travel, migration timeouts/invalid index, unexplained assets or location changes, lost journeys, increasing unprocessed events, unconfirmed broker publishing or incompatible consumer duplication effects. Keep valid paused ships paused. Lack of a production failed-jump trace remains an incident attribution gap, not evidence of a universal fix.

## Rollback boundaries and remaining dependencies

- Additive receipt/outbox tables can be installed before candidate code. Keep them, receipts and pending events on rollback; do not destroy replay/delivery evidence.
- A source rollback to v171 is only defensible **before any new receipt/event has been created** and after verifying compatibility/worker queues. Once receipts/outbox work exist, the old slug cannot enforce replay history or dispatch the new jobs. Stop ingress if necessary and prefer a compatible roll-forward build; do not blindly restore the old application.
- Never restore a deleted journey after completion/publication or reverse later player actions by restoring an old row. Broker confirmations do not prove external consumer deduplication, and published effects cannot be undone by PostgreSQL rollback.
- Do not roll back by restoring zero-invalid rows, weakening conditional guards, clearing queues, resetting ticks, changing brokers or refunding assets. No historical timing recomputation is part of rollback.
- Open external dependencies: consumer deduplication/ack behavior; external chat/jump UI response handling and an actual failed incident trace; owner review of5071's player-location discrepancy. Terra remains unavailable unless a separately authorized catalog/mechanics decision supplies a real route.

Local qualification/release preparation is complete when the recorded final checks pass with only the exact retained baseline failures, artifacts match source, and continuation lists M8 as unexecuted. Production closure requires a later authorized deployment/observation, not a zero count of legitimate interdictions.

## M8 authorization addendum

The owner has now explicitly authorized commit/deployment, the conditional migrations and production verification using this plan, with all valid interdictions kept paused and5071 unchanged. Execution evidence will be appended after rollout.
The existing external at-least-once delivery limitation remains disclosed; the proceed instruction authorizes operation with that boundary. Consumer deduplication remains unverified, and no artificial production delivery/jump will be used for verification.
A standalone ActiveRecord-only operator runner, script/apply_jump_travel_migrations.rb, loads only the four reviewed migration classes and no Rails initializers/models. It has explicit database/committed-SHA/phase gates, default dry-run, and before/after fingerprints for existing travel/ship/player/cargo state.
