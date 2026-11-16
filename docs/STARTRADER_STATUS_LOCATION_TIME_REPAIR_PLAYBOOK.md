# StarTrader — Status, Location, Jump, Admin & Time Repair Playbook

**Execution status:** READY TO KICK OFF, **CONDITIONAL FOR BEHAVIORAL CHANGES AND PRODUCTION RELEASE**  
**Source of truth:** `docs/STARTRADER_STATUS_LOCATION_TIME_DISCOVERY.md` (Claude discovery, 15 November 2026; inspected `4f42a56`)  
**Document type:** Multi-milestone execution and production-release plan  
**Final required state:** fixes committed, integrated into the main checkout, pushed to GitHub, deployed to the *verified* StarTrader production application, verified in production, and the *task-owned* feature worktree and temporary working files safely removed.

> This is an execution plan, not evidence that any fixes have been made. The discovery executed **zero application tests** because the isolated PostgreSQL connection lacked an authorized password. Reconfirm the current checkout and source before acting. Do not interpret test assertions discussed in the discovery as test runs.

## 0. Operating contract

This project repairs four user-facing requirements:

1. `POST /api/status` must reliably synchronize the intended `User`, `ShardUser`, and `UserShip` fields, especially `shard_users.last_location`.
2. `/admin/users/:id` must reveal every shard membership, player location, ship, and relevant travel state in a coherent modern layout.
3. Absolute timestamps exposed by the touched APIs must use unambiguous **integer Unix seconds**, with explicit display timezones. **Do not convert game ticks, tick counts, durations, or orbital simulation seconds into Unix time.**
4. Inter-system Jump (`POST /api/gate_travel`) must keep the player's and ship's named locations consistent at departure and arrival.

**Scope priority:** F-01–F-06, F-09, F-13, F-15, F-17–F-20, F-22 from the discovery, plus consistent ownership of location changes and tests. F-10/F-11/F-23 are security findings: contain them in a separately reviewed hardening milestone. F-07 JSONB re-encoding, F-08 legacy coordinate writer removal, F-12 15,000-credit behavior, F-14 travel-history redesign, and F-16 resolver optimization are **not** automatically authorized. Record them as deferred unless independently approved.

### Hard invariants

- `ShardUser.last_location` is a **merged JSON payload for named celestial location** (`id`, `name`, `location_name`, `star_system_name`, `classification`). Preserve any pre-existing legacy `x/y/z` keys. Do not fabricate coordinates or replace the payload with a string.
- `ShardUser#current_location` is a derived reader, **not** a database column. Do not add a competing location field.
- `UserShip.location_name` and `ShardUser.last_location` must be changed through a consistent, transactional authority rule.
- A server-authoritative active **or interdicted** `ShipTravel` outranks a client location observation. Status requests during travel still return normal **HTTP 200**, and **must not create, validate, mutate, or cancel** journeys.
- Arrival is controlled by the game tick. Keep ordinary speed at **1 Gm/tick**, existing minimum-duration rules, and the configured cadence (normally 15 wall-clock seconds/tick). Inter-system Jump has its own nominal 120-second policy. Do not change orbital time calibration.
- `arrival_tick = 0` is valid for a **paused/interdicted** journey. Never turn it into epoch zero or a Unix arrival date. Preserve minimum-one-tick resume and existing arrival exclusion rules.
- Do not change the positional RabbitMQ `ShipArrival` message format. No real broker sends in isolated tests. Jump must route to the selected broker environment; a dev Jump must never publish to production.
- Keep every existing response key unless an explicitly approved, consumer-verified compatibility change is planned. Add `*_at_unix`, warnings, and diagnostics additively.
- No silent cross-user `UserShip` transfer, arbitrary shard merge, player relocation, balance adjustment, production data backfill, force-push, destructive reset, or cleanup of someone else's files.
- Execute milestones in order, stop at hard gates, and mark **PASS / CONDITIONAL / BLOCKED / FAIL** honestly. A passing focused test suite does not substitute for an unrun full suite or production verification.

### Evidence and checkpoint discipline

At each milestone, create `docs/evidence/status-location-time/MXX/RESULT.md` recording: baseline SHA, changed files, tests actually run with counts and outcomes, relevant redacted diagnostics, findings resolved/deferred, decision IDs, rollback strategy, and go/no-go. Keep source findings referenced to the discovery; do not invent line numbers if the checkout has moved. Commit only task-owned files. Never log raw API secrets, OAuth tokens, production connection strings, or unnecessary personal information.

There are **two independent completions**:

1. **Engineering acceptance**: code, tests, compatibility, security, migration, and release candidate are green.
2. **Operational acceptance**: main/GitHub are synchronized, production actually runs the release SHA, smoke checks and monitoring pass, and the temporary worktree is removed. The project is **not COMPLETE** after engineering acceptance alone.

## 1. Decision register and project gates

The discovery's final verdict is **CONDITIONAL**. Capture owner decisions in `docs/evidence/status-location-time/DECISIONS.md` before the affected change. M00 and M01 may proceed while decisions are pending; do **not** convert a recommendation into implicit permission for a consequential behavior change.

| ID | Decision | Recommended default for owner review | Blocks |
|---|---|---|---|
| Q1 | Status location during active/interdicted travel | Ignore it for persisted locations, report `ignored_in_transit`, keep travel authoritative; allow idle updates | M03/M04 |
| Q2 | May Jump teleport a ship to a gateway it is not at? | **No**. Require actual origin-gateway co-location; reject without side effects. Four old tests currently assert teleportation and must be intentionally revised | M02 |
| Q3 | May status create an unknown shard? | Permit deliberate creation after normalized, collision-safe `channel_uuid` lookup; return `shard_created` warning; **never** silently split existing shard identity | M04/unique index |
| Q4 | May status reparent an existing ship to another player/shard? | **Fail closed unless explicitly authorized** by a separate, audited ownership workflow. The discovery proposed logging existing reparenting instead; record the chosen policy and the justification. Existing tests currently expect transfer | M04 |
| Q5 | Epoch precision | Integer **seconds**, no fractional values; keep existing ISO keys until consumers migrate | M05; default settled |
| Q6 | StarBitizen bot/client compatibility | Observe or obtain its real payload/consumer contract; additive keys first; do not silently alter paused `ship.time_remaining`, required `travel_guid`, or gateway behavior without checking the client | M02/M05/release |
| Q7 | 15,000-credit auto-grant on every status at zero | Defer. Moving to creation is a player-visible economy change outside the four requested defects | Only optional M06 |

**Known defaults D1–D6:** named location only; derived current location; use the light-modern admin styling from `admin/user_ships/edit`; add derived `arrival_at_unix`; defer JSONB recoding; do not revive completed travel history.

**Release gate legend**

| Gate | Non-negotiable proof |
|---|---|
| G0 — Baseline | Correct repository and all worktrees identified; working state preserved; isolated `bin/codex_test` baseline accessible; recovery and production topology established |
| G1 — Product decisions | Q1–Q4 recorded; Q6 consumer evidence or a deliberately nonbreaking fallback; no accidental economy change |
| G2 — Local quality | Each milestone's focused tests and the full `bin/codex_test` pass, or independently confirmed unchanged baseline failures are reported with explicit acceptance |
| G3 — Migration/data safety | Production duplicate audit, reversible additive migrations, backup and restore route verified; no automatic merging of divergent live players |
| G4 — Release candidate | Tested integration SHA, diff review, security/compatibility checks, nonproduction deploy or justified equivalent, rollback runbook |
| G5 — Production | Verified correct app/remote, deployed SHA, healthy migrations/workers/ticks, API/client and admin checks, monitored error and consistency signals |
| G6 — Cleanup | Local main/GitHub/prod SHA reconciled, task worktree clean and removable, evidence retained, no untracked user files destroyed |

## 2. Execution topology

**Historical project references only; verify before use:** GitHub `https://github.com/Seggellion/startrader.git`; Heroku Git remote `https://git.heroku.com/star-trader.git`; candidate Heroku app `star-trader`. These were documented in earlier StarTrader plans but are not proof of the current production mapping. **Discover** canonical `main`, remote names, auto-deployment settings, database ownership, release command, and Heroku app/domain before any push or deploy.

Use an isolated, project-owned feature branch/worktree. Do not change or remove the canonical main checkout, an unrelated worktree, the `.claude/` directory, the input discovery, or unrelated dirty files. The final merge must occur in, or be reconciled with, the **actual main checkout**. Respect branch protection and review mechanisms; never bypass them to satisfy a deadline.

### Proposed milestone sequence

| Milestone | Outcome | Main findings | Release status |
|---|---|---|---|
| **M00** | Environment, decisions, baseline, release topology | all / P-01–P-05 | gate G0 |
| **M01** | Read-only admin rebuild and production-safe audits | F-09, F-21, P-02–P-05 | candidate |
| **M02** | Correct Jump departure, arrival, idempotency, broker routing | F-01, F-02, F-15, F-22 | candidate; Q2/Q6 |
| **M03** | Unified location authority, atomic travel/arrival writes, instrumentation | F-03, F-20 and race paths | candidate; Q1/G3 |
| **M04** | Robust status sync, shard/user/ship resolution, responses | F-04, F-05, F-06, F-17–F-19 | candidate; Q3/Q4 |
| **M05** | Unix timestamps, paused countdown, explicit admin zones | F-13, time objective | candidate; Q6 |
| **M06** | Focused security and legacy-route containment | F-10, F-11, F-23 (approved scope) | candidate or documented deferral |
| **M07** | Cross-cutting regression, data reconciliation plan, full-suite acceptance | all | G2/G3 |
| **M08** | Release candidate and nonproduction qualification | all | G4 |
| **M09** | Merge main, push GitHub, deploy and verify production | all | G5 |
| **M10** | Postrelease proof, final reconciliation and safe cleanup | all | G6 / COMPLETE |

M00–M01 are safe to begin without decisions Q1–Q4. Subsequent milestones are gated; if an owner question remains unresolved, advance only independent, nonbreaking work and report the blocker.

## M00 — Revalidate checkout, decisions, tests, and deployment authority

**Goal:** turn the source-only discovery into a reproducible baseline and confirm the operational path that will eventually ship the code.

**Tasks**

1. Read `AGENTS.md`, the discovery, travel/interdiction release documents, `README.md`, test wrapper, and deployment configuration from the **current** checkout. Compare the discovered source paths and SHA to the current repository before relying on line references.
2. Read-only checks: `git status --short`, `git rev-parse --show-toplevel`, `git rev-parse HEAD`, `git branch -vv`, `git worktree list --porcelain`, `git remote -v`. Identify the main checkout, existing user-owned worktrees, clean/dirty files, branch protection, and upstream branch.
3. Use a **new isolated feature worktree** only if it can be added without disturbing existing work. Record its exact path and branch in the evidence ledger; label it as task-owned for possible M10 removal.
4. Locate configured app credentials and `bin/codex_db_doctor`. The discovery's test database failed with `fe_sendauth: no password supplied`; use authorized, documented credentials or request access. Do **not** copy passwords from another private `.env.*` merely because the file exists. Do not launch database-backed tests against production.
5. Run `bin/codex_db_doctor` then `bin/codex_test` once the isolated test DB is available; record baseline pass/fail counts and compare known historical failures. Run R-1–R-6 from discovery §12.4 as isolated **pre-fix reproductions**, labelled predicted until observed. If a production-data read-only audit is permitted, document counts only and protect identifiers.
6. Identify status HTTP request samples (redacted), StarBitizen client's shape and `ship.time_remaining` reliance, actual bot-driven Jump invocation and `travel_guid` behavior, and real production error patterns. No replay of state-changing production requests for diagnosis.
7. Record Q1–Q4 and Q6 ownership decisions with explicit owner acceptance; determine Q7 only if economy scope is subsequently approved.
8. Verify how main reaches production, production hostname, Heroku app/release identity, database and worker status, migration command, backups, rollback facility, and whether GitHub automatically deploys. A historical Heroku URL is **not** deployment authorization by itself.

**Required evidence:** `M00/RESULT.md` (baseline + exact repo/app identity), `DECISIONS.md`, safe production read-only audit queries/log sources. **PASS:** isolated test baseline can run, risks known, feature worktree registered, and release path discovered. **BLOCKED:** test DB unavailable or authority/identity ambiguous. Do not edit feature code while this is blocked.

**Recovery:** no database writes; dispose of no worktree until its ownership and contents are proven. Preserve any baseline failure artifacts.

## M01 — Admin user view and read-only integrity instrumentation

**Goal:** make player/ship divergence visible before altering writes, and measure the probable production data problems.

**Primary files:** `app/controllers/admin/users_controller.rb`, `app/views/admin/users/show.html.erb`, `app/views/admin/shared/_side_bar.html.erb`, `app/views/admin/user_ships/edit.html.erb` (styling reference), admin tests and a new **read-only** audit task.

**Implementation**

- Rebuild the show view using the light-modern `admin/user_ships/edit` token set inside the existing light admin layout. Use stacked sections, with user summary/status ribbon, `ShardUser` panels, location comparison, per-ship travel/cargo, and collapsed diagnostics/raw JSON. No unsupported claim of real last-seen or last-successful-sync data.
- Show each shard's `channel_uuid`, real `ShardUser.wallet_balance`, gameplay stats, named location, star system/classification, location-catalog resolution, legacy coordinate keys **only if present**, and raw `last_location` JSON. Label `users.wallet_balance` as legacy rather than gameplay balance.
- Show each ship's model, GUID, shard, `location_name`, cargo, current/paused/interdicted travel, `departure_tick`, `arrival_tick`, remaining ticks, broker environment. For paused `arrival_tick = 0`, label **interdicted sentinel**, not an arrival deadline. For no travel row, say **No journey on record**, not necessarily idle.
- Display player-versus-ship location per shard with an **Aligned / Diverged / Unknown / In transit** status and count divergences in the header. Distinguish stale catalog references from an absent location and zero values.
- Preload `shard_users`, ships, related models and travel; obtain current tick and seconds-per-tick once; batch-resolve `Location` names. Never query `ShardUser#current_location`, `User#active_ship`, `active_travel`, or `Setting.get` from inside display loops. Avoid an N+1 explosion with three shards and eight ships.
- Keep existing admin login and role check, cover authorization in tests. Replace third-party crafatar fallback with local initials; avoid sending `uid` to external services. Do not display secrets.
- Add navigation to ShardUsers. Use a read-only audit task reporting: `jsonb_typeof(last_location)` distribution; location key sets via Ruby (not JSON operators over double-encoded strings); casefolded `channel_uuid` duplicates; missing catalog references; per-user/per-shard ship/player divergences; and orphan associations. Redact user identifiers from summary output.

**Verification:** tests for multi-shard and multi-ship rendering, paused/zero sentinel, unusual legacy JSON (`{}`, string, native hash, null), missing associations, stale locations, bounded SQL query count, anon/player/admin authorization, and no outbound avatar. Run focused admin tests, isolated audit task, then full `bin/codex_test`.

**Gate/rollback:** no schema or live data writes. M01 is **PASS** only when the page and audit satisfy discovery acceptance criteria 11–21; capture sanitized before-state metrics to compare after deployment. Revert view/controller/task commits to undo.

## M02 — Jump synchronization and gateway integrity

**Goal:** fix the confirmed Jump soft-lock without changing game time, travel duration, or broker messages.

**Primary files:** `app/services/gate_travel_service.rb`, `app/controllers/api/gate_travel_controller.rb`, `app/services/ship_availability.rb`, relevant gate controller, arrival job and travel tests.

**Implementation**

1. Reproduce F-01/F-02 using discovery R-1, then write failing tests for departure and arrival player location **before** production code changes.
2. On accepted Jump, require a valid linked `ShardUser` or return an explicit domain error, never a raw `NoMethodError`. Normalize player and ship to the actual origin gateway and create exactly one `ShipTravel` in one transaction; do not partially relocate either on failure. Preserve the existing named-location merge behavior.
3. With Q2 approved, reject `gateway_name` when it does not identify the ship's actual origin location (same resolved `Location.id`). Do not make a remote gateway an implicit teleport. Intentionally revise the four legacy tests that assert teleportation; keep cross-system gateway resolution strict, including suffix handling.
4. Implement stable Jump idempotency: validate `travel_guid` ownership/retry semantics, prevent concurrent double-create with database-backed locking/uniqueness if appropriate. **Requiring a previously optional `travel_guid` is client-breaking**; gate this behind Q6 verification and a migration path. Never silently turn retries into new journeys.
5. Pass `rabbitmq` through the gateway request and store the same environment contract as normal travel. Stub broker sends in tests; assert `dev` never maps to `prod`.
6. Do not relax interdiction, paused status, arrival exclusion, or traveler co-location. The unified write path in M03 will supersede any transitional direct write; keep the M02 patch minimal and reviewable.

**Verification:** Jump accepted at real gateway, off-gateway rejection and no mutation, missing `ShardUser`, invalid destination, retries, concurrent requests, active/interdicted refusal, 120-second quantization, arrival to destination for both records, `rabbitmq=dev`, no production broker traffic. Run gate/arrival tests and full suite.

**Gate/rollback:** Q2 approved; Q6 client integration assessed. M02 **PASS** requires ship and player synchronized at departure and arrival with exactly one journey, without modifying an unaffected journey. Revert service/controller commit if needed; never attempt live remediation as rollback.

## M03 — One location authority and atomic travel lifecycle

**Goal:** replace competing location writers with an explicit owner and prevent status/travel races.

**Primary files:** new `app/services/location_sync.rb` (name may follow repo style), `app/models/shard_user.rb`, `travel_service.rb`, `gate_travel_service.rb`, `ship_travel_arrival_processor.rb`, `ship_availability.rb`, `ship_travel_controller.rb`, `api/ships_controller.rb`, tests and additive migration.

**Authority policy (Q1 must be signed off)**

| Situation | Winning authority | Player and ship write |
|---|---|---|
| Idle status, valid resolvable client location | Client observation | Apply atomically to both, preserve other JSON keys |
| Idle status, blank location | Existing database | No location write |
| Idle status, unresolvable name | Existing database | No location write; warn, continue other sync |
| Active/interdicted travel + any client location | `ShipTravel` | Ignore persisted client location, return 200 and travel state; report rejection |
| Travel/Jump departure | Server | Normalize both to actual origin atomically with travel creation |
| Arrival | Server | Commit ship and player destination together; idempotent under existing arrival lock |
| Cancel/interdict/resume | Existing lifecycle | No unapproved location change; preserve sentinel and recovery rules |
| Delivery/move/repair | Explicit service action | Validate no active travel and user/shard association; transaction, trace source |

**Implementation**

- Introduce one well-tested service for named-location writes and authority decisions; separate request identity resolution from mutation. Use a consistent lock order for `UserShip` / `ShardUser` / travel so concurrent status and arrivals cannot interleave incompatible writes or deadlock. Audit transaction boundaries. A read-only status *travel lookup* is allowed; creating or mutating `ShipTravel` in status is not.
- Make `TravelService` creation and both origin writes one DB transaction (currently three separate statements). Keep gate travel and arrival consistent. Retain arrival's existing locking, idempotency, minimum-one-tick resume, and correct broker routing; do **not** change broker transaction semantics without separate evidence and review.
- Remove the fragile requirement that player location exactly equal `travel.from_location_id` at arrival, **only after** the authority policy blocks newer in-flight client writes. Ensure arrival updates just the ship's linked player, not unrelated shard memberships or ships.
- Route `TradeService` location updates, travel, gate travel, arrival, repairs and `deliver_ship` through the one service. Gate `deliver_ship` while travel exists; never let it silently bypass travel authority. Do not alter non-location status, wallet, or game tick fields.
- Add an **additive nullable** migration: `shard_users.location_updated_at` (`datetime`) and `shard_users.location_source` (`string`); set by the owner service when a location actually changes. Sources may include `client_status`, `travel_departure`, `travel_arrival`, `repair`, `admin`. Null on historical rows means **Not recorded**, not proof no update occurred. No approximate backfill unless expressly approved.
- Keep the current `last_location` coder and mixed JSONB storage readable. **Do not re-encode production JSONB values** in this project. No unconditional divergence backfill; propose per-record repair plans for operator review only.
- Expand M01 admin diagnostics to display `location_source` and `location_updated_at` after the migration. Status warnings should identify rejections without echoing sensitive request values.

**Verification:** status/travel/Jump concurrency, rollback on final write failure, two concurrent arrivals, stale client observation during flight, interdicted status, legacy JSON keys preservation, nullable new fields and reversible migration. Explicitly assert travel rows unchanged by `/api/status`. Run all relevant focused suites and `bin/codex_test`.

**Gate/rollback:** G3 first: read-only production duplicate and schema checks, backup/restore path confirmed. Reversal of nullable columns is possible only after older code no longer depends on them; prefer rollback to prior **application** release without dropping them during incident response. No direct production data rewrite.

## M04 — Status reliability, identity and ship ownership

**Goal:** valid status traffic updates the right existing records even when optional name/location input is problematic.

**Primary files:** `app/services/trade_service.rb`, `app/controllers/api/trades_controller.rb`, `app/services/star_trader_ship_sync.rb`, `app/models/shard.rb`, `app/models/user.rb` where justified, migrations/tests.

**Implementation**

1. Keep `POST /api/status`, authentication (`X-Secret-Guid`), top-level/nested payloads, all existing response keys, idle client location sync, blank-value preservation, and in-transit HTTP 200 behavior.
2. **F-18:** unresolved optional `location` must no longer fail the entire sync. Apply valid username/wallet/association fields transactionally, leave both existing locations unchanged, return `200` with `location_resolution: "unresolved"` and a structured `location_unresolved` warning. Keep malformed authorization and genuinely invalid required inputs as errors.
3. **F-05:** resolve by stable `player_guid`/`twitch_id`, retain username uniqueness; an attempted collision must not seize another account or stop unrelated location/wallet updates. Return a `username_conflict` warning, not a fatal 422, for the legitimate resolved account.
4. **F-04:** normalize `shard_uuid` whitespace/casing consistently with `/api/travel`. Audit production `channel_uuid` duplicates **before** unique-index migration. For Q3-approved unknown shards, create once under safe uniqueness and warn `shard_created`; do not create duplicate siblings from case variation. If duplicates already exist, halt and present a **non-destructive, row-by-row reconciliation** preserving wallets, `ShardUser`, ships, and active travels. Do not auto-merge.
5. **F-06:** reconcile status and `StarTraderShipSync` ownership policy according to signed-off Q4. Default security recommendation is refusal/explicit authorized transfer, not `ship_guid`-only reparent. Never steal a ship from another player or another shard because a caller supplies its GUID; reconcile four existing tests that currently codify the old behavior only after owner decision.
6. **F-19:** select new versus legacy payload deliberately. `username + shard` continues working; `username + shard_uuid` without ship fields must not be routed into a five-required-field handler. Avoid ambiguous partial-new-path downgrade that could bypass authorization or ownership checks.
7. **F-17:** bound uniqueness retries in status and travel; use database constraints, transaction retries only for recognized transient races, and structured operational warnings; no unbounded loops.
8. Move logically coupled creations into suitable transactions or safe orchestration so a failure does not leave orphan Users/Shards/Ships or a half-associated ship. Keep unrelated `wallet_balance` and 15,000-credit economy rules unchanged without Q7.
9. Add `location_resolution: "applied" | "unresolved" | "ignored_in_transit" | "absent"` and `warnings: [{code, message}]` additively. Never include secrets in warnings.

**Verification:** discovery R-2 through R-5; new/legacy payload matrix; two users with case-colliding names; two differently cased shard UUIDs; unknown shard policy; cross-owner GUID attempt; repeated request; no location, invalid location; rollback and bounded retry; paused state; no accidental `ShipTravel` writes; no double-grant change. Rewrite existing tests intentionally changed by the approved contract rather than deleting them. Run focused ~60 status tests plus full suite.

**Gate/rollback:** Q1/Q3/Q4 must be recorded; production index creation only after casefold audit and a validated recovery path. Do not use destructive `dedupe!` or opportunistic data repair. Record every new response/status-code behavior for StarBitizen integration checks.

## M05 — Unix API instants, paused countdown, and timezone presentation

**Goal:** eliminate ambiguous real-world time reporting without disturbing the simulation clock.

**Implementation**

- Define `*_at_unix` as **integer epoch seconds in UTC**, JSON `null` when unknown. Datetime persistence remains existing UTC `datetime`; browser and admin format explicitly in a selected timezone with a zone label.
- Add a **derived, never-persisted** `arrival_at_unix` for active travel: approximately `Time.current.to_i + remaining_ticks * seconds_per_tick`; it is `null` when `is_paused` or `arrival_tick == 0`. Recompute per response; label as estimate because the tick chain may stall. Arrival decisions must keep using `arrival_tick <= Tick.current` and existing paused exclusions.
- Add the field to status, `/api/travel`, `/api/gate_travel` and `/api/location` **only where the relevant travel state is available**. Consider additive `server_time_at_unix` if the external bot needs a clock-skew reference; do not add an untested client dependency.
- Keep `departure_tick`, `arrival_tick`, `current_tick`, `remaining_ticks`, `time_remaining`, orbital simulation seconds and RabbitMQ positional message unchanged in meaning and format. Use `_tick` for tick point, `_ticks` for count, `_seconds` for duration, `_at_unix` for absolute instant, `_at` for Rails datetime.
- Audit the sole existing API ISO8601 field (`GET /api/commodities`, `"updated-at"`) and all other exposed absolute instants. Preserve existing ISO keys for compatibility, and if useful add a parallel Unix key with a documented transition. **No blanket type change to old response keys.**
- Make admin date rendering explicit (UTC by default, or a configured display zone), and remove implicit/unlabelled `strftime` and hidden hardcoded Pacific rendering. Test DST boundary and display-zone behavior.
- **F-13:** paused `ship.time_remaining` currently shows zero while `travel.time_remaining` is positive. Prefer one shared paused-aware calculation and test equality. This changes a legacy key's behavior: ship the change only after Q6 verifies the external consumer, or preserve the old key with a separately named additive paused-remaining value until client migration is agreed.

**Verification:** frozen clock, seconds versus JS milliseconds, UTC and DST, active/paused/resumed travel, `arrival_tick = 0` -> `arrival_at_unix: null`, tick-chain stall, Rabbit byte-for-byte contract, existing orbital and travel-timing tests. Run `test/services/travel_timing_pipeline_test.rb`, orbital suites, focused API suites and full tests.

**Gate/rollback:** passing tests plus external compatibility evidence. Do not advertise a fixed real-time ETA when the tick chain stalls; do not represent `arrival_tick=0` as `1970-01-01`.

## M06 — Security/legacy-route containment (separate decision)

Discovery flagged three routable hazards; they should be assessed before shipping a wider admin/API upgrade, but they are not permission to rewrite unrelated gameplay.

- **F-10:** `POST /api/increment_tick` is unauthenticated; `POST /api/set_tick` calls missing `Tick.set_current`. Inventory legitimate callers from logs/config; require appropriate authentication/authorization for a retained endpoint and prove unauthorized requests cannot mutate ticks. Do not modify tick mechanics to implement this.
- **F-11:** `GET /users` returns all users as JSON unauthenticated. Determine legitimate consumers; restrict it, minimize fields and add authorization tests, or obtain owner approval before removing the route. Do not expose sensitive identifiers.
- **F-23:** routed `MovesController#create` has a live `byebug`, undefined locals and legacy debugging. Verify usage, remove or disable broken action with reviewed route changes; prevent `byebug` from shipping as production behavior. Preserve any already tracked `.byebug_history` until content and ownership have been reviewed; never delete it blindly.
- **F-08, F-12, F-14, F-16, F-07:** stay deferred unless specifically approved with separate acceptance criteria, test budgets and rollback plans.

**Verification:** route/auth matrix, no accidental public exports, legacy client compatibility, unauthorized tick mutation refused, full suite. **Gate:** owner approval for route removals and economy changes; otherwise document explicit deferral and why release is still safe. No silent scope expansion.

## M07 — Cross-cutting integration and live-data safety review

**Goal:** assemble a coherent release candidate with no new soft-lock, stale write, or unvalidated data migration.

**Minimum acceptance matrix**

| Area | Must prove |
|---|---|
| Status | Good/blank/unresolved location; username collision; new/existing identities; case-variant shard; no unauthorized owner change; legacy payload; HTTP 200 during active/paused travel |
| Jump | Real gateway only (if Q2); player+ship origin and arrival; one journey on retry; missing `ShardUser`; interdicted/resumed; correct Rabbit environment |
| Concurrency | Status versus departure/arrival, two status calls, two Jump calls, repeated arrival; consistent lock order, no duplicate unfinished travel, no partial updates |
| Admin | 3 shards × 8 ships; real per-shard wallet, divergence and stale labels, interdiction sentinel, no N+1, authorization, no external UID leak |
| Time | Epoch integer/null, tick unchanged, no Unix epoch zero for interdiction, explicit timezone, DST, clock stalls and simulated/orbital axes preserved |
| Data | Historical JSON strings/objects readable; coordinate keys preserved; duplicate shard/ship/user GUID audits; no unapproved backfills |
| Integration | StarBitizen payload and response consumers; positional Rabbit event unchanged; CORS scopes unchanged, no production broker send during testing |

**Execution:** run focused suites, then `bin/codex_test` full baseline; confirm all intended old assertions are updated only where policy changed. Run static checks, security-sensitive route tests, and database migration up/down in an isolated test environment. Record failure classifications against M00 baseline. Produce a **read-only** production reconciliation proposal with counts and exact but protected affected record IDs for operator review. Do not merge live data or auto-move players because two location fields disagree.

**PASS:** no unexplained test regressions, approved decisions trace to implementation, migration compatibility demonstrated, and explicit data-fix plan exists for any observed legacy inconsistency. If an externally consumed contract remains unverified, mark CONDITIONAL and block the affected release feature rather than inventing compatibility.

## M08 — Release candidate, nonproduction rehearsal, rollback packet

**Goal:** make the same immutable changeset deployable, traceable, and recoverable.

1. Review the full diff against M00: no secret changes, untracked user files, unintended schema/credit changes, environment leakage, tick drift, or extra CORS origins. Include `bundle`/framework checks as configured, not invented commands.
2. Rebase or integrate from canonical main only after preserving the original feature commits and confirming the main checkout is safe. Resolve conflicts with fresh tests; never force-push protected history.
3. Produce a named **release candidate SHA** and immutable evidence manifest: GitHub target, migration list/order, expected response changes, Rabbit contract, affected routes, signed-off decisions, and rollback refs.
4. Verify a **restorable production backup or snapshot**, not merely a scheduled backup entry. Check migration forward/back behavior and older-code compatibility, especially nullable new columns and uniqueness constraints. If duplicates exist, halt the index migration and create a separate reviewed plan.
5. Deploy the candidate to a properly isolated nonproduction environment where feasible; check Admin UI, fixture-backed status/Jump, jobs/ticks, Rabbit environment, `arrival_at_unix`, and auth. If no safe staging environment exists, explicitly present alternative qualification evidence and seek a go/no-go decision; do not test real jumps on arbitrary live users.
6. Prepare `docs/evidence/status-location-time/M08/RELEASE_PACKET.md` with live preflight checklist, migration and rollback ordering, production smoke scripts, success thresholds, monitoring duration, named operator, and the verified platform-specific deploy mechanism. Avoid storing secrets.

**PASS / G4:** release candidate SHA is fixed; tests green; backup/restore and deploy authority verified; nonproduction qualification passed (or justified with signed alternative). No production action yet if these conditions are missing.

## M09 — Merge to main, push GitHub, deploy production and verify

**This milestone is mandatory.** User-requested end state includes publication, not a local-only patch. Do not stop after a feature-branch commit, unmerged PR, or passing unit tests.

### Preflight: GO/NO-GO

- Confirm exact canonical **main checkout**, upstream GitHub branch, release candidate SHA, current working-tree cleanliness, approvals, and whether branch protection requires a PR. Preserve unrelated changes; if main is dirty or diverged, stop and arrange safe integration instead of resetting it.
- Confirm **verified production application** and remote mapping; check Heroku app identity and domain against configured production authority, release history, workers and database. The historical `star-trader` name is a clue, not definitive proof.
- Verify production backup/restore, migration prerequisites, all G0–G4 decisions, current live baseline (`/api/status` 400/422 rate, case-variant shard count, divergence count, API health, tick heartbeat, pending/interdicted travel, arrival message flow). Read-only queries only.
- Establish rollback triggers: unexpected status error-rate increase, new ship/player divergence, failed migration, stopped tick chain, duplicate unfinished journeys, unauthorized access, or wrong Rabbit environment. Prepare rollback command **for the verified deployment provider**; do not guess a remote or release number.

### Integration and GitHub publication

1. Finish review and commit task-owned docs/code/tests in the feature worktree. Keep the discovery, playbook, decision register, and milestone evidence as tracked project documents.
2. Integrate feature work into the actual main checkout using the repository's prescribed PR or local merge procedure. If policy requires PR checks/approval, honor them; do not bypass protection. Verify the main checkout contains the feature commits, run the required post-merge checks, and record the **final main SHA**.
3. Push the merged main branch to verified GitHub `origin` without force, confirm the remote main ref reflects the intended main SHA, and confirm CI/review requirements. If it auto-deploys to production, **observe that one deployment** rather than initiating a second competing release.

### Production deployment

4. Deploy **the exact verified main SHA** through the documented production path (for example the configured Heroku Git or GitHub integration, if verified). Ensure deploy artifact provenance equals GitHub main; never deploy an unmerged feature branch or a different local tree.
5. Apply approved additive migrations in the platform's required sequence **once**, with recorded release IDs and database state. Do not run destructive deduplication, unapproved location backfills, or manual tick alterations.
6. Confirm web process, background jobs, tick chain/watchdog, Rabbit routing, database migration version, application logs, and that the application is serving the release SHA.

### Production verification and monitoring

7. Use read-only endpoints/administrative observation and a **dedicated approved test identity** for any status or Jump smoke that would otherwise mutate live user state. Never send a trial `POST /api/status` for arbitrary players—it writes data. Do not perform a real jump, delivery, or interdiction on someone else's live ship.
8. Verify the rebuilt Admin user page on representative read-only records: shard memberships, wallets, named location and ship divergence, paused `arrival_tick=0`, correct labels and timezone. Check authorization using safe accounts.
9. Verify status for both idle and travelling cases, warnings for unresolved locations and username collisions (isolated test identity only), approved ship ownership policy, and stable broker environment. Confirm `arrival_at_unix` is integer or null as designed, never confused with ticks.
10. Monitor at least **30 minutes** (or one sufficiently complete operational window agreed before deploy) for status 4xx/5xx rates, divergence trends, duplicate travels, tick/watchdog recovery, arrival jobs, Rabbit messages and application health. Compare to M00/M01 baseline. Keep recording live results; do not assume silent logs prove health.
11. On rollback trigger, follow the prepared recovery sequence: revert or roll back the **application release** while keeping compatible additive columns when necessary, verify ticks and jobs, and record incident evidence. Stop any M10 cleanup until recovered and approved. Do not automatically apply destructive reverse migrations or rewrite affected player locations.

**PASS / G5:** main checkout SHA = GitHub main SHA = deployed application source SHA (or a documented build artifact referencing it); migration and worker state healthy; approved smoke passes; monitoring finds no unexplained regression. Record deployment/release ID, timestamp (UTC), production identity, verification evidence, and rollback status.

## M10 — Release closure and safe removal of task worktree

**Goal:** leave a clean, canonical main checkout with no leftover task-owned worktree or temporary working files, while retaining everything needed for audit and rollback.

1. Confirm M09 **PASS**: GitHub main and local main integrated, production running the intended SHA, monitoring completed, and no rollback in progress. If any proof is missing, stop with **CONDITIONAL** and retain the worktree for recovery.
2. Copy/commit all task-owned evidence, source changes, generated release reports, and the discovery/playbook into the canonical main history. Ensure no unique work remains only in the feature worktree or an unpushed branch.
3. Run `git worktree list --porcelain` and `git status --porcelain=v1` **in the exact task-created worktree**. Verify path, branch, clean state, merged SHA, and ownership. Also inspect the canonical main checkout; never remove it.
4. Remove **only** the verified, clean task-owned feature worktree using `git worktree remove <exact-validated-path>` (no force). If not clean, do not run `git clean -fdx`, `rm -rf`, `git reset --hard`, or `git worktree remove --force`; preserve the contents and report what requires review.
5. If and only if the feature branch is wholly integrated and its SHA recorded, delete the **local task-owned branch** using normal safe branch deletion. Do not delete main or remote user branches without separate approval.
6. Remove only explicitly enumerated **disposable** scratch outputs belonging to this project and already archived or reproducible (temporary logs, isolated build outputs). Preserve uploaded source, user-created files, backups, evidence, release manifests and other worktrees. Do not wipe the workspace root.
7. Confirm `git worktree list` no longer includes the task worktree, local main is clean, and GitHub and production remain synchronized. Mark any retained temp files or recovery branches with a reason instead of claiming cleanup is complete.

**PASS / G6:** production verified, SHA reconciled, final evidence in main, designated worktree removed, disposable task working files removed, and unrelated content intact. **BLOCKED:** any dirty/unmerged work, unknown ownership, unresolved deployment incident, or inability to verify exact targets. Cleanup is never a reason to destroy unrecoverable work.

## 3. Final acceptance contract

The project may be called **COMPLETE** only if every item is true:

- [ ] All four requested objectives have passing regression evidence and the recorded decisions have been honored.
- [ ] `POST /api/status` persists appropriate player/ship updates when idle; returns 200 with warnings on unresolvable optional location and username collision; never mutates a journey.
- [ ] Jump leaves player and ship aligned at real origin and destination, with idempotent journey creation and correct environment-specific broker behavior.
- [ ] Admin user view displays each `ShardUser`, true per-shard wallet, named `last_location`, ship/player mismatch, and correctly labelled interdiction/unknown state, without N+1 or access leaks.
- [ ] All touched API absolute instants follow Unix-seconds convention, timezone display is explicit, tick/orbital semantics unchanged, and external clients are compatible.
- [ ] No unexplained full-suite failures; positive isolated database and deployment checks; safe migration and backup evidence.
- [ ] Final code is integrated in the **local main checkout** and published to **GitHub main** with recorded SHA.
- [ ] The **verified production application** is running the intended SHA; live checks and monitoring passed.
- [ ] Evidence and rollback packet are committed, production release recorded, and **only** task-owned feature worktree and disposable working files were removed.

### Final report format

```
StarTrader status/location/time repair: COMPLETE | CONDITIONAL | BLOCKED | FAILED
Main checkout SHA:
GitHub main SHA:
Production app + release ID + deployed SHA:
M00..M10 verdicts:
Focused/full test counts:
Decisions and compatibility sign-offs:
Migration / backup / rollback status:
Live status, Jump, Admin, tick, broker checks:
Task worktree removed? (exact path):
Temporary working files removed? (exact enumerated paths):
Deferred findings and owner follow-ups:
```

No generic “deployed successfully” claim without the production release identity and observed checks. No “cleaned up” claim without inspection of the exact removed worktree and known scratch files.
