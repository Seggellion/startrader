# Orbital calibration release evidence

23 October 2026. Production execution and observation are pending until the completion record below is filled. Baseline discovery remains historical evidence.

## Approved contract and decisions D01–D09

Dustin authorized documented simulation parameters in chat. These are simulation choices, not measured game alignments. All 14 supplied targets are constant circular star-relative radii. Stellar mass determines period, while the catalog's equal periapsis/apoapsis sets each radius. The model evolves with tick time.

| System | Mass kg | Body: radius Gm, phase degrees at epoch |
| --- | ---: | --- |
| Stanton | 1.98847e30 | Hurston: 13, 0; Crusader: 20, 75; ArcCorp: 30, 160; MicroTech: 42, 250 |
| Pyro | 1.590776e30 | Pyro I: 8.2, 10; Monox: 10.6, 80; Bloom: 17.8, 150; Pyro IV: 47.6, 35; Pyro V: 47.6, 215; Terminus: 68, 300 |
| Nyx | 2.386164e30 | Nyx I: 5, 20; Delamar/Levski: 15, 110; Nyx II: 25, 200; Nyx III: 48, 290 |

Catalog `orbital-v1:fefc269b0e50f896`; epoch `2026-10-23T00:00:00Z`, tick origin 0, simulation seconds origin 0, 604800 simulated seconds per tick. Existing `hours_per_tick` changes do not alter this version's anchor; a future clock change requires a new anchored catalog version. Production wall scheduling remains 15 real seconds/tick. Explicit phases are independent of array order and primary keys. Pyro IV/V remain distinct, opposite, 95.2 Gm apart.

Identity uses system/classification/source API ID, reviewed name and parent constraints. Three stars, 14 hosts and Levski make 18 validated identities. Levski explicitly inherits Delamar at zero local offset. Ordinary cities/outposts can inherit a known body center and are labeled `host_center_approximation`. Unmeasured moons/stations, including Arial, return unavailable; they are omitted from the map with an explicit unavailable count. No invented local orbit or intersystem distance is used.

The immutable code catalog wins over imported reference fields; imports/admin edits cannot change protected identities or delete calibrated hosts. Admin edit pages identify effective calibration values. No schema migration, persisted orbital elements, stellar masses, ship speeds or existing journey durations are changed. The only planned production write is the guarded ArcCorp external identity repair described below.

Numerical ship speed stays unchanged and means Gm/tick. Production has 242 ships, positive speeds all 2 and one invalid speed. New ordinary travel uses `max(ceil(distance_Gm / speed), 2)`. Gateway 120-real-second timing, normal system policy, pause/resume sentinel and saved trips retain their existing behavior. Quote keys `from`, `to`, `distance`, `current_tick` remain; metadata/XYZ/version/units are additive. Distance numbers intentionally change from legacy scene separation to physical Gm. External StarBitizen source was not accessible; repository consumers were audited and corrected, and response keys retained. A client assuming legacy scene units must adopt the explicit `distance_unit` contract.

Map presentation is nominally 1 scene unit/Gm; camera fit, label/mesh size and zoom are presentation only. One server snapshot supplies renderer, quotes and travel. Tick is captured once; safe read endpoints do not create ticks, journeys or broker messages. Browser abort/sequence/version checks prevent stale fetches from replacing a newer snapshot. New digested assets activate with the server release; older open pages need a full reload to use the new renderer.

## Verified environment and baseline

- App `star-trader`, UUID `6b362b75-1732-42a4-9888-669a393f7f82`; domain `startrader.altama.energy` verified bound to it.
- Heroku Git remote `https://git.heroku.com/star-trader.git`; heroku-24, Ruby buildpack, no pipeline coupling. Web and worker are Basic dynos. Deployment is exact-commit Git push.
- `DATABASE_URL` attachment: `postgresql-metric-14477`, resource `fc11b830-1f31-42ef-a2c8-518712e07568`, database `d3o2aaoe4mit3m`, PostgreSQL 16.14. Authenticated read-only audit, not inferred from a cached remote.
- Previous release **v163**, release UUID `e37ef132-012b-46da-93d0-2848c8e6c8e6`; slug `78059fa2-e53e-4d97-b3e4-8fdeca57138c`; deployed SHA `fecb49f619bf69eeeef9beb50a037dc7a95469a7` verified from slug metadata.
- Audit found five paused unfinished journeys, all arrival_tick=0, and no ordinary active journeys. Release captures and compares a nonidentifying aggregate fingerprint of stored timing/routing state.
- Branch `codex/orbital-calibration`; origin main revalidated at the baseline. GitHub main unprotected; no repository rulesets or mandatory checks discovered. Existing unrelated `.claude/` worktree/content preserved.
- Isolated local PostgreSQL role `startrader_orbital_test`, non-superuser; separate test, celestial-only preview and SQL rehearsal databases. Private ignored environment files are not committed. Test startup forbids real Bunny sessions; actual foreign keys stay enabled with read-only FK validation.

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

Before-image: ArcCorp PK1366, name ArcCorp, classification planet, Stanton system/parent, id_star_system68, code ARC, api_id NULL. Local canonical source API ID is 4. Planned single-field diff: `api_id: NULL → 4`; no timestamp or other field changes.

`script/orbital_identity_repair.sql` locks exactly that row and checks every identity field, current API ID and scoped source uniqueness in a transaction. It is idempotent. `script/orbital_identity_rollback.sql` restores only this API ID to NULL after the same identity guard; conflicting later values fail. Forward twice, inverse twice, unrelated field preservation and conflict rejection passed in a separate scratch database. The planned celestial export validates all 18 identities.

Activation order: revalidate unchanged v163/app/database → capture completed Heroku backup and aggregate travel fingerprint → guarded repair → validate production celestial identities against candidate → integrate verified source → deploy exact integrated commit → verify slug SHA/dynos/catalog/assets → safe quotes and Chrome → observe at least 15 minutes. No arrivals or travel creation are release probes.

Concrete operator commands (run from WSL project root with normal Heroku login; redirect stdin except SQL file input):

```bash
HEROKU_SKIP_UPDATE_CHECK=1 heroku pg:backups:capture DATABASE_URL --app star-trader </dev/null
HEROKU_SKIP_UPDATE_CHECK=1 heroku pg:psql DATABASE_URL --app star-trader < script/orbital_identity_repair.sql
git push heroku "${STARTRADER_RELEASE_SHA}:refs/heads/main"
HEROKU_SKIP_UPDATE_CHECK=1 heroku releases:info --app star-trader --json </dev/null
HEROKU_SKIP_UPDATE_CHECK=1 heroku run --exit-code --app star-trader 'bundle exec ruby script/orbital_calibration.rb --tick 10 --from-id 338 --to-id 1018 --speed-gm-per-tick 2' </dev/null
```

The pure Ruby diagnostic does not boot Rails, open RabbitMQ, create ticks or mutate data. Local/export equivalent: `bin/codex_exec ruby script/orbital_calibration.rb --input PATH --tick 10`. `orbital:validate` Rake task also omits the Rails environment dependency.

On a documented rollback trigger: `heroku rollback v163 --app star-trader </dev/null`, verify both dynos and fresh old assets; only if restoring the missing API ID is required, run the narrow inverse SQL after guards. No full database restore or recalculation of saved journeys is part of routine reversal. Completed Heroku backup is a last-resort recovery point requiring separate assessment of intervening activity.

## Completion record

Integration SHA, production backup/release, live verification and observation interval will be appended after execution. M7/M8 are pending at candidate preparation.
