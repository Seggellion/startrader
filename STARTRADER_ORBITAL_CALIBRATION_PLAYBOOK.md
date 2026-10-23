# StarTrader orbital calibration project playbook

Date: 23 October 2026
Owner: Dustin Hill
Starting evidence: supplied StarTrader orbital calibration discovery, inspected at `fecb49f619bf69eeeef9beb50a037dc7a95469a7`
Status: M0–M5 complete; M6 qualification passed and integration is in progress. M7/M8 pending. Actual decisions and evidence are in STARTRADER_ORBITAL_CALIBRATION_RELEASE.md.

## Project outcome and execution authority

Correct StarTrader’s existing evolving orbital model so Pyro, Nyx, and Stanton use the requested physical star-distance calibration. Make server travel calculations and the orbital display agree on identity, hierarchy, mass, units, and simulation time. Preserve practical presentation comparable to current Stanton. Deliver and verify the completed release in StarTrader production.

Stellar-mass adjustment is explicitly in scope. Retaining the evolving model supersedes the earlier suggestion to default to static positions. Mass changes period and phase; it cannot independently set the requested orbital radii. Calibrate orbital distances, mass, phase/time, and presentation as separate concerns.

This document authorizes no actions by itself: it is the execution plan for the requested project. When the accompanying kickoff prompt is used to start implementation, carry the work through production within the user’s authorized scope. Do not stop after creating a branch, patch, or release candidate. Ask only for essential unresolved product decisions, missing access, or an applicable explicit policy requirement; continue work that does not depend on the answer. Do not spawn agents unless separately authorized by the user or applicable repository instructions.

## Evidence and nonnegotiable constraints

- Work in `/home/dusti/startrader` using Linux Git inside WSL. The origin found during discovery was `https://github.com/Seggellion/startrader.git`. Revalidate current state and instructions before editing. Preserve unrelated `.claude/` content and the existing `claude/friendly-leakey-963229` worktree.
- Browser testing and release qualification must use **Google Chrome only**. Headless Chrome is acceptable if confirmed as Google Chrome; do not substitute Chromium, Firefox, WebKit, or an unverified browser binary.
- The Heroku remote found was `https://git.heroku.com/star-trader.git`. **`star-trader` is a candidate app, not a verified production identity.** Do not deploy to the earlier unverified `startrader-production` name or another project’s app.
- The production host observed was `https://startrader.altama.energy`. Cached `heroku/main` and successful public payloads do not establish the live release SHA or app/domain/database binding.
- Database and Heroku authentication were unavailable during discovery. No Rails test, browser test, Rails boot, asset build, live quote, or travel-state audit was completed. Replay baselines are not production quotes.
- Retain direct separation at departure, normal-travel system restrictions, gateway behavior, ceiling and minimum-duration rules, saved in-flight travel, and RabbitMQ environment routing.
- Never treat an unknown coordinate as `(0,0)`. Never calculate intersystem separation by subtracting independent local origins. Do not fabricate missing moon or station measurements.
- Keep supplied target values unchanged. Do not multiply them by five, replace them with external catalog numbers, or adjust stellar mass as if it alone could produce the radii.

## Calibration inventory

Observed IDs are Location primary keys on the public host, not portable UEX identities. Resolve catalog entries using audited classification, system, and stable source identity; use names as reviewed constraints. Validate uniqueness and ancestry before applying overrides.

| System | Intended object and aliases | Observed canonical record | Target Gm | Application rule |
| --- | --- | --- | ---: | --- |
| Pyro | Pyro 1 / Pyro I | Pyro I, PK 1015 | 8.2 | Star-relative target. |
| Pyro | Monox / Pyro 2 | Monox, PK 1016 | 10.6 | Same intended object for both aliases. |
| Pyro | Bloom / Pyro 3 | Bloom, PK 1017 | 17.8 | Same intended object for both aliases. |
| Pyro | Pyro 4 / P4 | Pyro IV, PK 338 | 47.6 | Separate star-parented planet in observed data. |
| Pyro | Pyro 5 / P5 | Pyro V, PK 1018 | 47.6 | Separate planet; equal radius does not imply equal position. |
| Pyro | Terminus / Pyro 6 | Terminus, PK 1019 | 68.0 | Same intended object for both aliases. |
| Nyx | Nyx 1 / Nyx I | Nyx I, PK 979 | 5.0 | Star-relative target. |
| Nyx | Nyx 2 / Nyx II | Nyx II, PK 980 | 25.0 | Star-relative target. |
| Nyx | Levski | Levski, PK 1190; host Delamar, PK 1099 | 15.0 | Apply orbital calibration through Delamar; preserve city inheritance. |
| Nyx | Nyx 3 / Nyx III | Nyx III, PK 981 | 48.0 | Star-relative target. |
| Stanton | Crusader | Crusader, PK 834 | 20.0 | Star-relative target. |
| Stanton | Hurston | Hurston, PK 891 | 13.0 | Star-relative target. |
| Stanton | microTech | MicroTech, PK 965 | 42.0 | Preserve current canonical spelling. |
| Stanton | ArcCorp | ArcCorp, PK 1366 | 30.0 | Star-relative target. |

Observed star PKs: Pyro 1510, Nyx 1501, Stanton 1256. Current Pyro/Nyx primary apsides are largely 147/152; Stanton includes Hurston 60/60, Crusader 100/100, MicroTech 210/210, ArcCorp 147/151. Current star masses are serialized as 166500000.0 without a trustworthy cross-runtime mass contract. Re-audit rather than treating these observations as present database state.

## Calculation and compatibility contract

Use physical **Gm**, explicit **kg**, and simulation **seconds** at clear boundaries. `1 Gm = 1,000,000 km = 1,000,000,000 m`. Keep full precision internally. Existing `G = 6.67430e-38` is dimensionally appropriate for Gm cubed per kg per second squared. Display `Gm`, not `GM`.

Keep the existing planar scope with XYZ output and `z=0`; no new inclination or gravity engine is required. Define the orbital target as one of circular radius, semimajor axis/nominal distance, or distance at an explicit acceptance epoch. For circular targets, periapsis and apoapsis both equal the target. Do not set both bounds this way for an unapproved elliptical interpretation.

Use an explicit epoch, tick origin, per-body phase, simulated seconds per tick, and dataset version. Derive time from an anchored tick mapping, not browser page load or an unanchored subtraction from Unix time. If tick duration can change, specify how existing anchors remain continuous. Use real scheduling seconds only for wall-clock arrival presentation and existing gateway timing.

Positions must be deterministic functions of the same data version and simulation instant. Compose parent/local coordinates recursively with cycle and missing-parent checks. Preserve a documented zero local offset for unmeasured cities; this is a body-center approximation, not surveyed surface geometry. Label station heuristics and unavailable nested positions honestly.

Direct distance is the Euclidean separation of physical world positions in one system at one departure tick. Capture that tick once per quote/travel calculation. Reject unsupported cross-system direct quotes; preserve `GateTravelService` and its existing `ceil(120 / real_seconds_per_tick)` rule.

The provisional compatibility choice is to retain numeric ship speed and explicitly define its calculator rate as **Gm per simulation tick**. This follows the clarified practical Stanton scale. Audit every speed writer and caller before finalizing it. Do not silently use km/s, Gm/s, or the superseded blanket `5 * speed` conversion. With approved rates, preserve `max(ceil(distance_gm / speed_gm_per_tick), 2)` for new ordinary travel. Preserve pause/resume behavior and `arrival_tick=0` as the interdiction sentinel; never recalculate existing saved trips from the new geometry.

Use a nominal display mapping of **1 scene unit per Gm** for the calibrated primary orbits, subject to Chrome visual qualification. It preserves current Stanton’s approximate unpadded extent: Hurston 12, Crusader 20, MicroTech 42, ArcCorp 29.4–30.2 scene units. Mesh size, zoom, padding, and camera fit must never alter physical positions or distances.

## Decision register

Resolve these once and record evidence, selected option, consequences, and owner. Code inspection can resolve implementation choices; product accuracy inputs require a supported source or Dustin’s decision.

| ID | Decision | Starting recommendation or requirement | Gate |
| --- | --- | --- | --- |
| D01 | Meaning of each target | Explicit circular radius or documented elliptical/epoch interpretation; never infer full elements from one number. | M1 before target implementation. |
| D02 | Stellar mass per system | Explicit kg from a supported dated source, a desired period plus radius, or an approved simulation mass. No magnitude heuristic or invented production mass. | M1 before evolving-model acceptance. |
| D03 | Phase and epoch | Reproducible per-body phase at an anchored time. Independent supported angles for Pyro IV/V; no array-order, hash, or database-ID phase assignment. | M1 before position acceptance. |
| D04 | Fidelity to actual game angles | State source/version and allowed approximation; targets alone cannot establish angular accuracy. | M1 and final claims. |
| D05 | Identity and host | Audit stable composite identities; Levski inherits Delamar; retain separate observed Pyro IV/V unless contrary evidence exists. | M1/M2. |
| D06 | Authority and persistence | Code-shipped immutable versioned catalog, resolved through one effective-data layer; importer values cannot displace overrides. | M2. |
| D07 | Speed and API compatibility | Retain numeric speed with explicit Gm/tick after caller audit; inventory external response consumers and version any incompatible change. | M1/M4. |
| D08 | Missing nested data | Explicit unavailable result/error; documented host-center city approximation; no invented local orbits. | M3/M5. |
| D09 | Deployment sequence | Verify app/domain/database, exact release process, and any persisted data reversal. | M1 identity audit and M7 release gate. |

If mass/phase/target semantics cannot be established, present one compact request containing the specific remaining choices and their effects. Continue identity audits, catalog architecture, error handling, and independent tests meanwhile. Do not hide an arbitrary choice inside a passing test.

## Milestone execution rules

For each milestone record `Pending`, `In progress`, `Blocked`, or `Complete`; exact commit; files changed; commands actually run; meaningful results; remaining limitations; and next action. Keep a project status section in this playbook and a separate evidence log if needed. Proposed paths and new task names below are implementation deliverables, not claims that those files or commands already exist.

Complete relevant tests before advancing. After a new change, conflict resolution, or integration commit, rerun affected checks. Do not add redundant test rounds after an unchanged candidate already passes. Preserve existing repository policies without inventing approval requirements.

## M0 Discovery baseline

**Status:** Documentary discovery complete. Runtime access gaps remain open inputs to M1.

Retain the supplied discovery as `STARTRADER_ORBITAL_CALIBRATION_DISCOVERY.md` at the repository root, preserving its evidence classifications. It inspected `fecb49f619bf69eeeef9beb50a037dc7a95469a7`; source citations apply to that commit, not automatically to current HEAD.

Recorded defects include physical coordinates divided by 5 on the server; a browser solar-mass guessing heuristic absent on the server; real versus simulated tick disagreement; omitted browser ancestry; importers overwriting apsides/mass; a quote tick race and missing frame guard; and `StarBitizenRun#distance` subtracting periapsides.

The replay used synthetic tick 10, 3600 simulated seconds/tick, and speed 100 legacy scene units/tick. It produced zero separation for Pyro I–Monox and Nyx I–II, and 8 scene units for Hurston–Crusader. These are diagnostics, not accepted game positions or production durations. The independent 13/20 Gm same-ray probe returned 1.4 scene units where physical geometry requires 7 Gm.

**Exit evidence:** Discovery retained without rewriting replays as live observations. No rollback action is needed; no runtime changes were made.

## M1 Revalidate access and settle the model contract

**Prerequisite:** M0. **Work:** repository, access, read-only data audit, D01–D05 and D07–D09.

1. Check current branch, HEAD, worktrees, remotes, diff, and applicable instructions. Fetch only through the project’s normal authenticated route; compare current source with the discovery commit. Create an isolated feature branch/worktree without disturbing existing work.
2. Inspect `bin/codex_exec`, `bin/codex_test`, test configuration, initializers, and environment handling. Use Ruby 3.2.2 and Bundler as actually configured. Prove development and test database identity and test isolation before any `db:prepare` or test helper that can migrate.
3. Arrange normal authentication if absent. Verify the exact production app UUID, domain binding, database attachment, deployed release SHA, dynos/workers, and release mechanism. Do not search for credentials or print configuration secrets.
4. Audit Location source IDs/classifications/system/parent chains and duplicate normalized aliases, external-ID collisions, cycles, and missing data. Audit actual tick settings, persisted star fields, ship-speed distributions/writers, and in-flight/interdicted aggregates through genuinely read-only database queries.
5. Audit API consumers, including StarBitizen, for existing distance units/response expectations. Establish a compatibility/versioning plan before changing numerical response semantics.
6. Record D01–D05/D07 decisions, chosen clock anchor, masses/phases and provenance, speed boundary, and realistic accuracy limits. Identify invalid nested bodies that need explicit unsupported handling.

Starting read-only commands, after inspecting any wrapper for side effects:

```bash
cd /home/dusti/startrader
git status --short
git rev-parse HEAD
git worktree list
git diff --stat
git remote get-url origin
git remote get-url heroku
bin/codex_exec --ruby-diagnostics
HEROKU_SKIP_UPDATE_CHECK=1 heroku apps:info --app star-trader --json
HEROKU_SKIP_UPDATE_CHECK=1 heroku domains --app star-trader
HEROKU_SKIP_UPDATE_CHECK=1 heroku releases --app star-trader
HEROKU_SKIP_UPDATE_CHECK=1 heroku pg:info --app star-trader
```

These Heroku commands inspect a candidate; their presence does not prove it is the correct app. Use explicit read-only transactions for database audits. Rails boot currently opens RabbitMQ; `TICK_BOOTSTRAP=true` may enqueue jobs; `Tick.current` may create a row. Do not assume console, dashboard, websocket, or “read” endpoints are side-effect-free. `GET /api/location/:user_ship_id` can process arrivals and is excluded from diagnostics.

**Exit:** Actual identities and access recorded, test isolation proven, calculation contract signed off in the decision log, and remaining unsupported fidelity stated. Missing production access blocks release, not independent local implementation. Unresolved numerical masses/phases block claiming a calibrated evolving model.

**Recovery:** Read-only work has no data rollback. Preserve any documentary changes and existing worktree state.

## M2 Introduce durable orbital calibration data

**Prerequisite:** M1 identity and target contract. **Likely files:** `app/models/location.rb`, importer services under `app/services/admin/data/`, new catalog/resolver/validator, associated tests.

1. Add an immutable, versioned code catalog, for example `config/orbital_calibrations/v1.yml`, containing the 14 mappings, resolved host identities, effective apsides/target semantics, explicit stellar masses, phases/epoch, units, provenance, and validation rules.
2. Implement one effective-data resolver used by physics, serializers, and admin diagnostics. Preserve raw imported fields where practical. Calibrated fields take precedence consistently; never maintain a browser-only copy.
3. Resolve by audited composite identity. Abort a calibration mapping on duplicate/missing identity or parent mismatch; do not fuzzy-match and mutate an unintended record. Unknown nested bodies can be explicitly unavailable without suppressing the entire valid system.
4. Audit every orbital writer: planets, moons, stations, star systems, generic locations, cities, outposts, and admin edits. Ensure reimport, nil payloads, and mass defaults cannot overwrite the effective catalog. Normalize empty parents and prevent numeric IDs being silently interpreted as parent names where the effective graph relies on them. Scope changes to required integrity and calibration behavior.
5. Add a read-only `orbital:validate` task and a baseline/diagnostic task with documented arguments. They must avoid `Tick.current`, imports, writes, travel processing, and RabbitMQ publication. Report raw/effective values, identity, graph errors, units, version, and a supplied tick. Make the no-write behavior testable.
6. Prefer no database migration for calibrated values. If repository evidence requires persistent fields, document a separate scoped migration/update, dry-run diff, before-image journal, replay/idempotency checks, and guarded reversal before applying it.

**Verification:** All 14 mappings; alias collision rejection; repeat runs unchanged; import replay on isolated records; star-mass precedence; Delamar/Levski ancestry; separate Pyro IV/V; missing identity fails explicitly; terminal/facility links unchanged. Verify actual active serializers, not only the new resolver in isolation.

**Exit:** One durable effective source of orbital truth with a version and validated consumers. New task commands are documented and run locally.

**Rollback:** Revert the catalog/resolver commit. Restore any persisted changes only from the scoped before-image after checking current values; do not overwrite intervening edits.

## M3 Correct evolving physical positions and clock behavior

**Prerequisite:** Approved mass, phase, epoch, and target contract; M2 authority layer. **Likely files:** `planet_position_calculator.rb`, `location.rb`, clock/channel serialization, new physical snapshot service and tests.

1. Make the authoritative position API return physical XYZ in Gm with system identity, canonical IDs, parent identity, mass kg, captured tick/time, and catalog version. Eliminate `UNIT_SCALE=5` from physical outputs.
2. Correct and validate the existing orbital equations/solver, dimensional period calculation, eccentricity handling, and phase anchoring. Do not introduce a new gravity simulator. Reject invalid bounds, nonpositive required masses, or nonfinite inputs explicitly.
3. Implement deterministic recursive parent composition with missing-parent and cycle detection. Keep unmeasured cities at documented host center; isolate unavailable local orbits rather than fabricating them.
4. Separate simulated seconds per tick from real scheduling seconds in server snapshots and channel messages. Preserve existing fields for older consumers where compatible. Use one captured clock and version for a calculation; define reload, stopped-clock, reconnect, and tick-setting changes.
5. Give equal-radius Pyro IV/V independently justified phases. Verify they are separate objects; equal distance is permitted only when the chosen geometry actually yields it.

**Verification:** Independent fixtures in the acceptance matrix below, fixed-clock repeatability, period scaling with mass, quarter-period phase evolution, parent composition, nil and invalid inputs, high-eccentricity cases if supported, and snapshot metadata. Use absolute `1e-9 Gm` plus relative `1e-12` as the proposed geometric tolerance, adjusting only with documented solver evidence. Define a separate time/phase tolerance.

**Exit:** The evolving physical model meets the approved target interpretation and time contract; its numerical precision is distinguished from game fidelity.

**Rollback:** Revert the physical model and snapshot changes together with incompatible data contracts. No existing travel should have been rewritten.

## M4 Integrate physical distance into quotes and new travel

**Prerequisite:** M3. **Likely files:** `location.rb`, `api/distance_calculator_controller.rb`, `travel_time_calculator.rb`, `travel_service.rb`, `star_bitizen_run.rb`, consumer tests.

1. Route distance callers through the authoritative physical snapshot. Capture the departure tick once and use it for response metadata and calculation.
2. Add explicit system/frame validation and unknown-position errors. Preserve existing name-based clients while introducing explicit IDs/system context and reviewed aliases as needed; reject ambiguous inputs.
3. Expose unambiguous Gm, tick/time, canonical IDs, and catalog version in the quote contract. Implement the M1 compatibility decision for existing clients before switching them to new numeric units.
4. Feed physical Gm into the audited Gm/tick speed boundary. Preserve ceiling, minimum 2, invalid-speed behavior, same-endpoint travel rejection, gateway service, saved departure/arrival/duration, pause/resume, and RabbitMQ environment routing.
5. Replace `StarBitizenRun#distance` with the same explicit clock/physical contract, or deprecate its physical-distance claim after proving callers do not require it. Do not leave radius subtraction as a second authoritative distance implementation.
6. Reproduce baseline routes with a fixed snapshot, old and new results, approved actual speed samples, raw ticks, and service minima. Explain intended duration changes. Do not force synthetic defaults to mimic production.

**Verification:** Quote/request tests for same-system routes, cross-system rejection, aliases, ambiguity, invalid locations, and tick-boundary race. Service/lifecycle tests prove existing in-flight and sentinel records are not recomputed and outbound messages retain their environment. Exercise mutating travel only in an isolated nonproduction environment with mocked/excluded external delivery.

**Exit:** API and new-travel paths consume correct physical distance under a documented compatibility contract. Existing saved travel semantics remain intact.

**Rollback:** Revert calculator, rate-boundary, and consumer contract changes coherently. Never recalculate all saved travel as a rollback strategy.

## M5 Align the orbital interface and qualify in Google Chrome

**Prerequisite:** M3 and the stable snapshot contract; M4 before end-to-end qualification. **Likely files:** `star_system_controller.js`, `CelestialBody.js`, `animation.js`, `OrbitCreator` if active, orbital partials, channel consumer.

1. Carry canonical identity, ancestry, unit, clock, and version into the active browser path. Remove the magnitude-based solar-mass guess. Prefer server-owned physical state; any client propagation must match fixed server fixtures under the same contract.
2. Compose hierarchy consistently. Use the 1 scene unit/Gm nominal primary scale, presentation-only mesh size/padding, and appropriate camera fit for all three systems. Do not feed scene coordinates into labels or quotes.
3. Fix the tick-before-fetch race, initial tick loading, reload/system-switch behavior, paused rendering, reconnect, and out-of-order or mismatched-version snapshots. A browser must not silently mix versions during deployment.
4. Correct active distance labels to physical Gm. The discovery found no active browser quote form and no `#distances` container: verify the actual visible interface and avoid building a new calculator UI unless needed for the existing product.
5. Inspect labels, occlusion, selection, parent-child presentation, and practical Stanton extent. Missing nested positions must be explained or omitted with an explicit unavailable state, never rendered at a fake origin.

**Chrome checks:** Fixed server tick versus rendered positions; all three systems; target stars/body radii; Pyro IV/V distinction; Levski/Delamar host behavior; parent offsets; initial load; tick arriving before fetch; reload; system switch; stopped clock; reconnect; zoom/camera independence; console/network errors; and version mismatch recovery. Confirm the actual Google Chrome binary in test evidence. Use existing Capybara/Selenium conventions where available.

**Exit:** Active Chrome interface is readable and agrees with authoritative physical data; geometry and quotes are independent of presentation transforms.

**Rollback:** Revert source modules and deploy fresh compatible asset digests. Never patch `public/assets` digests by hand.

## M6 Complete regression qualification and release preparation

**Prerequisite:** M2–M5. **Work:** targeted regression suite, relevant full suite, assets, release manifest and commands.

1. Run meaningful Rails model/service/request/lifecycle tests and Chrome checks in the proven isolated environment. Inspect `bin/codex_test` before using it: it installs dependencies and runs `db:prepare`. Prevent test RabbitMQ connections and tick bootstrapping through the repository’s verified test setup; do not invent a production-disabling flag.
2. Run relevant broader tests once the targeted checks pass. Record failures honestly, including pre-existing failures and their relevance. Do not qualify a release on pure-source replay alone.
3. Run a terminating asset build/precompile in a safe build environment. The existing npm CSS command uses `--watch`; it is not a release check. Confirm the actual CSS build and Rails asset commands, new source digests, and serving paths.
4. Integrate through the repository’s normal branch/PR policy. Record the exact integrated SHA and run affected checks on that candidate. Do not force-push or bypass branch protections.
5. Write a release manifest with app UUID/name, domain, database attachment identity, previous release/SHA, candidate SHA, catalog version, chosen masses/epoch/phases, test evidence, Chrome binary, speed/API compatibility, build outputs, optional migrations/data commands, activation order, smoke checks, and rollback commands.
6. Choose a compatible deployment sequence for old/new server responses, assets, channels, and any persisted state. Prefer additive preparation followed by activation where a single release would mix contracts. If no database updates are needed, explicitly record that.

Typical commands after environment isolation and wrapper inspection, adjusted to actual test paths:

```bash
bin/codex_exec bundle exec rails test
bin/codex_exec bundle exec rails test:system
```

Run `test:system` only with a configured verified Google Chrome driver. Validate any required local preparation separately. Asset and Heroku release commands must be resolved from current project configuration, not copied speculatively from another app.

**Exit:** Exact deployable candidate passes required checks; data and code reversal are concrete; production identity and access are current; no material mass, phase, speed, or target decision remains hidden.

**Rollback:** No production release yet. Revert local candidate changes coherently; preserve evidence and isolate any optional local data reversal.

## M7 Deploy the verified candidate to StarTrader production

**Prerequisite:** M6 complete. **Work:** production only through the verified release route.

1. Recheck app/domain/database binding, latest production release, and candidate SHA. Stop deployment if another release changed the baseline; reconcile and requalify only the affected parts.
2. Capture a recoverable Heroku database backup and a scoped orbital before-image when persisted state will change. Record backup completion and restoration procedure. Even with a code catalog, record the database/schema compatibility of the release and rollback.
3. Record read-only aggregate in-flight/sentinel state and current catalog/clock context without triggering travel or arrivals. Plan a compatible worker transition if needed; do not clear queues or restart travel indiscriminately.
4. Deploy the tested integrated SHA through the verified route. If direct Git deployment is the established route and the verified remote is still `star-trader`, use the exact recorded SHA rather than an unchecked local branch. Otherwise use the discovered pipeline/CI mechanism.
5. Run only planned migrations/data steps, in the tested order. Restart only required dynos/processes and let the release load new assets/catalog/memoized state. Validate any activation/version transition.
6. Record the actual Heroku release ID and deployed SHA. A successful Git push alone is not evidence of a successful release.

Conditional direct-Git example, valid only after the app, remote, candidate, and deployment route have been verified:

```bash
git rev-parse --verify "${STARTRADER_RELEASE_SHA}^{commit}"
git push heroku "${STARTRADER_RELEASE_SHA}:refs/heads/main"
HEROKU_SKIP_UPDATE_CHECK=1 heroku releases --app star-trader
```

`STARTRADER_RELEASE_SHA` is a task-specific variable populated from the release manifest. Do not push before M6 passes, use `--force`, or assume pushing origin also deploys production.

**Exit:** Actual candidate release is running on the verified production app; catalog/data activation and assets are correct. Immediately continue to M8.

**Rollback triggers:** Wrong app/version, invalid calibrated identities, missing critical assets, new quote 5xx/nonfinite distances, clock divergence, unexpected travel/lifecycle mutation, or major map failure. Follow the recorded release/data reversal; do not improvise destructive recovery.

## M8 Verify production and close the project

**Prerequisite:** M7. **Work:** live non-mutating verification, Chrome inspection, observation, final handoff.

1. Check live release SHA, catalog version, star mass units, epoch/clock metadata, all 14 effective mappings, and compatible source assets. For ellipses verify the accepted target meaning, not a false requirement that radius is constant.
2. Repeat fixed-time representative calculations for each system with the deployed model. Use the new read-only diagnostic or an authenticated safe query path. Compare with independently computed fixture expectations and the release manifest. The quote endpoint has no fixed-tick input in the old contract; do not claim reproducibility from two requests at different ticks.
3. Verify the quote endpoint through its documented POST only after proving the revised path does not create tick/travel data or send messages. Check errors for cross-system/unknown inputs. Do not POST `/api/travel`, process due arrivals, or use `GET /api/location/:user_ship_id` as a smoke test.
4. Inspect all three orbital maps in Google Chrome, including reload, system switch, live/stopped clock, and physical distance labels where actually present. Compare practical Stanton framing with the baseline.
5. Check logs/error rate and observe for at least 15 minutes and several actual tick broadcasts, extending if the live cadence requires it. Compare aggregate travel/sentinel behavior with normal activity; distinguish expected lifecycle progression from release-induced changes. Record the interval and evidence rather than claiming indefinite monitoring.
6. If a rollback trigger fires, restore the recorded previous compatible release and any narrowly scoped changed data, then verify service recovery. A full database restore is a separate last-resort recovery operation that risks unrelated activity; do not use it as routine rollback.
7. Update milestone status and deliver a closeout listing deployed release/SHA, catalog version, target coverage, test/Chrome/live results, duration compatibility, retained approximations, and any unsupported nested locations. Report access or fidelity blockers explicitly if the project cannot meet the release gates.

**Exit:** The intended release is verified in StarTrader production. A local pass, merged PR, deployed-but-unverified build, or missing required calibration decision is not project completion.

## Independent acceptance matrix

All angles below are synthetic fixtures, not observed game alignment. Target/phase/mass provenance is assessed separately. Use a fixed epoch/tick and dataset version; full physical positions and raw durations must be available to the test.

| Check | Independent expectation |
| --- | --- |
| Unit conversion | 8.2 Gm = 8,200,000 km; 47.6 Gm = 47,600,000 km. |
| Same ray, radii 13 and 20 Gm | Distance 7 Gm. |
| Opposite rays, same radii | Distance 33 Gm. |
| Right angle, same radii | Distance sqrt(569), approximately 23.8537208838 Gm. |
| Equal radii 47.6 Gm, opposite phases | Distance 95.2 Gm, not zero. |
| Parent (10,0,0), child offset (0,0.001,0) Gm | Child (10,0.001,0); parent-child separation 0.001 Gm. |
| Circular radius with positive mass changed | Radius unchanged; period changes in inverse square root proportion to mass. |
| Circular propagation | Quarter period advances phase by pi/2 under the chosen orientation. |
| Direct identity/reversal | Same physical endpoint has zero distance; direct distance is symmetric at the same time. Same-endpoint travel policy remains separate. |
| Clock loading and reload | Same authoritative tick/version yields the same position regardless of page-load timing or frame rate. |
| Presentation transforms | Camera zoom, mesh size, and padding do not change physical distance or travel duration. |
| Unsupported parent or local orbit | Explicit unavailable/error result, never a fake star-origin position. |
| Different systems | Direct quote rejects unrelated frames; existing gateway duration stays unchanged. |
| Duration boundary, positive speed | Ceiling and ordinary minimum 2 remain; no unconditional fivefold speed rewrite. |
| Existing journeys and interdiction | Stored duration/arrival/remainder retained; `arrival_tick=0` remains a sentinel. |
| Writer durability | Reimport and admin/raw field updates cannot silently replace calibrated effective data. |
| Release identity | Live app/domain/release SHA and effective catalog match the tested manifest. |

Required route evidence: Pyro I–Monox; Nyx I–Nyx II; Hurston–Crusader; Levski–Delamar; Pyro IV–Pyro V; Hurston–Arial. The last route may expose missing or implausible moon data: either validate its existing local orbit with evidence or return an explicit unsupported result. Do not assert nested-route realism merely because primary radii are calibrated.

## Execution status (23 October 2026)

| Milestone | Status at kickoff | Completion evidence |
| --- | --- | --- |
| M0 | Complete for documentary discovery | Supplied discovery; runtime gaps carried to M1. |
| M1 | Complete | Access, identities, contract, decision log. |
| M2 | Complete | Catalog, precedence, safe validation task. |
| M3 | Complete | Evolving physical model and clock tests. |
| M4 | Complete | Quotes, travel compatibility, lifecycle tests. |
| M5 | Complete | Google Chrome and physical/display agreement. |
| M6 | In progress | Qualification: 153 tests/749 assertions, assets passed; integration pending.  Integrated candidate and release manifest. |
| M7 | Pending | Actual production release identity. |
| M8 | Pending | Live checks, observation, closeout. |

Execution evidence: STARTRADER_ORBITAL_CALIBRATION_RELEASE.md records D01–D09, approved simulation parameters, authenticated production identity, test isolation, regression limitations, fixed-clock comparisons, Chrome qualification and guarded SQL repair/inverse. Starting M0 access limitations above remain historical observations. No production calibration has yet been activated.
