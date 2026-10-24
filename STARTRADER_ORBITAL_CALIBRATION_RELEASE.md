# Orbital calibration release evidence

23 October 2026. Production execution and the required observation are complete; see the completion record below. Baseline discovery remains historical evidence.

## Approved contract and decisions D01–D09

Dustin authorized documented simulation parameters in chat. These are simulation choices, not measured game alignments. All 14 supplied targets are constant circular star-relative radii. Stellar mass determines period, while the catalog's equal periapsis/apoapsis sets each radius. The model evolves with tick time.

| System | Mass kg | Body: radius Gm, phase degrees at epoch |
| --- | ---: | --- |
| Stanton | 1.98847e30 | Hurston: 13, 0; Crusader: 20, 75; ArcCorp: 30, 160; MicroTech: 42, 250 |
| Pyro | 1.590776e30 | Pyro I: 8.2, 10; Monox: 10.6, 80; Bloom: 17.8, 150; Pyro IV: 47.6, 35; Pyro V: 47.6, 215; Terminus: 68, 300 |
| Nyx | 2.386164e30 | Nyx I: 5, 20; Delamar/Levski: 15, 110; Nyx II: 25, 200; Nyx III: 48, 290 |

Catalog `orbital-v1:fefc269b0e50f896`; epoch `2026-10-23T00:00:00Z`, tick origin 0, simulation seconds origin 0, 604800 simulated seconds per tick. Existing `hours_per_tick` changes do not alter this version's anchor; a future clock change requires a new anchored catalog version. Production wall scheduling remains 15 real seconds/tick. Explicit phases are independent of array order and primary keys. Pyro IV/V remain distinct, opposite, 95.2 Gm apart.

Identity uses system/classification/source API ID, reviewed name and parent constraints. Three stars, 14 hosts and Levski make 18 validated identities. Levski explicitly inherits Delamar at zero local offset. Ordinary cities/outposts can inherit a known body center and are labeled `host_center_approximation`. Unmeasured moons/stations, including Arial, return unavailable; they are omitted from the map with an explicit unavailable count. No invented local orbit or intersystem distance is used.

The immutable code catalog wins over imported reference fields; imports/admin edits cannot change protected identities or delete calibrated hosts. Admin edit pages identify effective calibration values. No schema migration, persisted orbital elements, stellar masses, ship speeds or existing journey durations are changed. The only production data change was the guarded ArcCorp external identity repair described below.

Numerical ship speed stays unchanged and means Gm/tick. Production has 242 ships, positive speeds all 2 and one invalid speed. New ordinary travel uses `max(ceil(distance_Gm / speed), 2)`. Gateway 120-real-second timing, normal system policy, pause/resume sentinel and saved trips retain their existing behavior. Quote keys `from`, `to`, `distance`, `current_tick` remain; metadata/XYZ/version/units are additive. Distance numbers intentionally change from legacy scene separation to physical Gm. External StarBitizen source was not accessible; repository consumers were audited and corrected, and response keys retained. A client assuming legacy scene units must adopt the explicit `distance_unit` contract.

Map presentation is nominally 1 scene unit/Gm; camera fit, label/mesh size and zoom are presentation only. One server snapshot supplies renderer, quotes and travel. Tick is captured once; safe read endpoints do not create ticks, journeys or broker messages. Browser abort/sequence/version checks prevent stale fetches from replacing a newer snapshot. New digested assets activate with the server release; older open pages need a full reload to use the new renderer.

## Environment verification

Production app/domain/database binding, prior source revision, web/worker state, recoverable backup and guarded single-field identity repair are recorded in a local operator manifest. Operational identifiers and journey fingerprints are intentionally omitted from this public summary. No credentials or private environment files are committed.

Local tests use a non-superuser role and separate test, celestial-only preview and SQL rehearsal databases. Actual foreign keys remain enabled; test startup forbids real Bunny sessions. Existing unrelated worktree/content is preserved. Integration uses normal pull requests and verified source commits.

## Qualification completed

`CODEX_ENV_FILE=.env.orbital-test bin/codex_test` with orbital core/snapshot/catalog/integration, travel service/controller, planet positions, gateways, saved trips, RabbitMQ routing/sender and command-center request paths: **153 tests, 749 assertions, 0 failures/errors/skips**. Log `tmp/orbital-final-qualified.log`.

Independent checks cover 7/33/sqrt(569)/95.2 Gm geometry, exact unit conversion, nested XYZ, mass/period behavior, quarter-period propagation, invalid/eccentric elements, clock/version, all target radii, reimports, deletion/identity protection, same-time quotes, explicit unavailable responses and actual new travel creation in an isolated database. Existing lifecycle tests use fake geometry while separate integration tests exercise actual calibrated distance and numeric ship speed. Broker is faked in tests only.

Broader suite: 436 runs, 1752 assertions, 35 failures, 30 errors. Starting commit under the same isolated DB/test safety infrastructure: 414 runs, 1271 assertions, 31 failures, 123 errors. Comparison of failing test identities found **no new failing identities** (65 current versus 154 baseline). Legacy admin authentication/routes/trading fixtures prevent a globally green suite; these are not represented as passing. Logs `tmp/orbital-full-suite.log`, `tmp/orbital-baseline-suite.log`.

Terminating `RAILS_ENV=test SECRET_KEY_BASE_DUMMY=1 bin/codex_exec bundle exec rails assets:precompile` passed, including Tailwind. Map controller digest `986e75c8646b6e042687124f756be2860374d45596275b90eb77261e8c023b8b`; CSS `7a4b315494d5b91eed96fe315f209e02dc9f5816e0e6c07dd928ff35f200c589`. Existing Browserslist freshness warning does not fail the build. `git diff --check` passed.

Google Chrome only: verified installed Google Chrome `155.0.8059.41` at `C:\Program Files\Google\Chrome\Application\chrome.exe`. Celestial-only preview at stopped tick 0: all three maps expose exact target radii, separate IV/V and Levski/Delamar; repeated reloads are deterministic, rapid system switching leaves the final system, zoom leaves physical labels unchanged. Version mismatch/error handling covered in requests and browser source review. No orbital console errors observed; unrelated existing Google Maps key warnings remain. Final production browser evidence is recorded below.

## Fixed-clock before/after evidence

This is a replay of celestial-only production data, **not a historical live quote**. Both models use supplied tick 10, 604800 simulated seconds/tick, numeric speed 2. Before is exact original calculator source at the baseline SHA, whose outputs are scene units. After uses the new catalog, Gm and planned ArcCorp identity repair. Full precision XYZ and clock/version are in `ORBITAL_CALIBRATION_ROUTE_EVIDENCE.json`.

| Route | Legacy scene distance / duration ticks | New Gm / duration ticks |
| --- | --- | --- |
| Pyro I–Monox | 0 / 2 | 4.9504954366011775 / 3 |
| Nyx I–Nyx II | 0 / 2 | 24.39981310353593 / 13 |
| Hurston–Crusader | 8.000000000000002 / 5 | 29.682407353154375 / 15 |
| Levski–Delamar | 0 / 2 | 0 / 2 (host-center approximation) |
| Pyro IV–Pyro V | 0 / 2 | 95.2 / 48 |
| Hurston–Arial | 10 / 5 | Explicit unavailable: unmeasured Arial local orbit |

The legacy 8.000000000000002 value rounds up to five ticks at speed two in the actual old implementation. Same-host zero geometric distance still preserves the two-tick ordinary minimum for distinct destinations. Same-endpoint departure policy remains separate.

## Production data operation and rollback

Before-image: ArcCorp PK1366, name ArcCorp, classification planet, Stanton system/parent, id_star_system68, code ARC, api_id NULL. Local canonical source API ID is 4. Executed single-field diff: `api_id: NULL → 4`; no timestamp or other field changes.

`script/orbital_identity_repair.sql` locks exactly that row and checks every identity field, current API ID and scoped source uniqueness in a transaction. It is idempotent. `script/orbital_identity_rollback.sql` restores only this API ID to NULL after the same identity guard; conflicting later values fail. Forward twice, inverse twice, unrelated field preservation and conflict rejection passed in a separate scratch database. The activated production celestial export and pure diagnostic validate all 18 identities.

Executed activation order: revalidate prior release/app/database → capture completed Heroku backup and aggregate travel fingerprint → guarded repair → validate production celestial identities against candidate → integrate verified source → deploy exact integrated commit → verify slug SHA/dynos/catalog/assets → safe quotes and Chrome → observe at least 15 minutes. No arrivals or travel creation are release probes.

Operator deployment and rollback commands, prior release identifiers and completed backup details are retained locally. The pure Ruby diagnostic does not boot Rails, open RabbitMQ, create ticks or mutate data. Local/export equivalent: `bin/codex_exec ruby script/orbital_calibration.rb --input PATH --tick 10`. The `orbital:validate` Rake task omits the Rails environment dependency. Routine reversal never restores the entire database or recalculates saved journeys.

## Completion record

M0–M8 are complete. Implementation integrated through PR #22 and presentation refinement through PR #23. Integrated source is `2a89c6c9f10ae401450c158861cd3deae9fb2192`; deployed source was independently verified through authenticated release/slug metadata and both web/worker processes. Operational release identifiers, completed backup and exact observation timestamps remain in the local operator manifest.

Final observation lasted **15 minutes 30 seconds**, with **61 ticks** of progress and six bounded infrastructure health samples. No HTTP5xx, infrastructure error code or process crash appeared in those samples. This is a bounded observation, not indefinite monitoring or a claim about all application logs. Production payload logs were excluded to preserve privacy.

Final read-only checks independently validated all 14 target radii, three stellar masses in kg, 18 identities, anchored clock/version, five representative live quotes, four expected error cases and three fresh page-referenced asset files. Existing saved-journey state remained unchanged. No mutating travel endpoint or arrival-processing GET was used as a probe.

Google Chrome verified all three live maps, distinct Pyro IV/V, Delamar/Levski, zoom-independent physical labels, rapid system switching, reload and later actual tick broadcasts after reconnect. Local stopped-clock behavior was verified separately; production tick scheduling was not paused for testing. Console error checks were empty. The temporary preview server was stopped.

The detailed local operator record is `tmp/orbital-private-release-manifest.md`; supporting local machine evidence includes `tmp/orbital-closeout.json`, `tmp/orbital-live-smoke.json`, and nonidentifying health summaries in `tmp/orbital-health-observations.jsonl`. These ignored local files are not public repository artifacts. The final closeout commit changes documentation only; it does not replace the verified deployed source SHA above.

Retained limits: simulation masses/phases are documented design choices, not measured game ephemerides; unmeasured moon/station geometry is explicitly unavailable; ordinary surface sites use host-center approximations; the broader legacy suite still has the failures documented above.

### Live-phase label refinement

Live Google Chrome verification exposed clustered inner Pyro labels. Labels now occupy nonoverlapping screen rectangles with leader lines, without changing mesh positions, physical data, clock or travel calculations. Qualified in the celestial-only preview at fixed tick 696350 across all three systems, with no console errors. The terminating asset build passed. The completed production observation followed this presentation refinement.

Updated CelestialBody digest `0922e02a952a90ab71dcdf1d478871e66f5dd3099ee8a77544cfc4176fba0cfc`; CSS `0926b72b94edd0e07e8daa67d6c4ccae8de704d16b7a6d44e3c10c0db6c3684f`. No further data step or schema change.

### Orbital progression follow-up

The subsequent nested-orbit release is recorded in `STARTRADER_NESTED_ORBITS.md`. The 0.01 orbital-rate correction is documented in `STARTRADER_ORBITAL_RATE_CORRECTION.md`; production v167 is activated and verified after 16m10s / 63 ticks, with seven post-activation health samples and unchanged saved journeys. Running source is `682cb21c78344b9ff9b4aba3a8160006207f6d2f`, catalog `orbital-v3:cfc59e789927b6af`, effective multiplier 0.01 from tick 696781. It preserves calibrated geometry and the global clock while integrating orbital time through a versioned activation anchor. After that anchor activates, use its phase-safe append-only rate reversal procedure; earlier plain source-rollback recipes would discard the slow-time history.


Final production Chrome recheck completed on 23 October 2026 (Pacific): all three systems across actual ticks, reload/reconnect, moon/station neighbourhoods and 170 same-tick rendered-mesh/server comparisons pass. Multiplier 0.01 and the original anchor are retained, with no Chrome console errors. Twelve live quotes and unchanged saved journeys were revalidated. The earlier deferred browser check is resolved; detailed rates and the bounded client-interruption exception are recorded in `STARTRADER_ORBITAL_RATE_CORRECTION.md`. Production remains v167 at source `682cb21c78344b9ff9b4aba3a8160006207f6d2f`; this evidence update is not redeployed.

Travel timing follow-up, 24 October 2026: see `STARTRADER_TRAVEL_TIMING_RELEASE.md` for the requested uniform 1 Gm/tick ordinary policy and 15-second real cadence, deterministic actual-Tick arrival tests, route samples and release/rollback evidence. This supersedes the historical use of each ship's numeric reference speed for new ordinary journeys; it preserves saved journey timing and all orbital calibration/slowdown parameters.
