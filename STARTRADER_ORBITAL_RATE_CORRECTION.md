# Orbital progression correction

23 October 2026. Production v167 is deployed, activated and verified; the required post-activation observation is complete. This document supplements the historical calibration and nested-orbit release evidence.

## Diagnosis and implementation

Authenticated production revalidation found release v166, source `782b2fe3b5faa3f8432f17b7f241163ed6f69da3`, catalog `orbital-v2:bbe91ae886034b0c`, with both web and worker running. Fresh celestial payloads and actual tick samples match that source. No duplicate orbital advancement or seconds conversion defect was found. TickJob/TickRunner increment the shared tick under existing locks; the browser fetches server positions and renders them without propagating time. The previous orbital mapping advances 604800 seconds per tick, producing multiple revolutions for some inner bodies.

`Orbital::Clock` now owns the single `orbital_progression_multiplier`. The immutable, content-versioned catalog `orbital-v3:cfc59e789927b6af` carries an ordered activation schedule. Activation is scheduled at tick **696781**, with inherited orbital seconds **421413148800**. Global `simulation_seconds` and the base `simulated_seconds_per_tick=604800` remain unchanged. Only `orbital_seconds` passed to Kepler propagation changes. At activation tick A, orbital seconds equal the old mapping exactly; subsequent ticks advance by `604800 × 0.01 = 6048` orbital seconds. The slope of the first interval after A is reduced, while the position at A remains continuous. Historical ticks retain their previous positions.

Server snapshots, distances and future travel quotes share that one mapping. Tick/status broadcasts expose the same orbital seconds, multiplier, effective step, active anchor and full clock schedule. Browser assets continue to render server snapshots, with actual mesh coordinates exposed as read-only DOM diagnostics for deterministic qualification. There is no second browser multiplier.

All v2 body entries are retained exactly: 14 primary radii, every stellar/planetary/moon mass, phases, parents, 18 moon and 60 station models, offsets and units. No schema or production data changes are required. Ship speed remains Gm/tick; real scheduling, duration ceiling/minimum, gateway timing, saved journeys, interdiction and resume behavior are unchanged. Paused simulation retains identical positions across reloads and process restarts.

## Qualification

Focused suite: **192 tests, 3400 assertions, zero failures/errors/skips**. It covers unwrapped angular ratios, periods in ticks, exact activation continuity/history, every nested body's one-old-tick versus 100-new-tick position, unchanged body definitions/radii/units, catalog reload/restart, phase-safe reversal, invalid schedules, generator guards, quote/map/broadcast/channel agreement, saved journeys, lifecycle, travel/gateway/broker routing, tick cadence and watchdog scheduling. Chord length is explicitly excluded as an angular-rate ratio.

Broader suite: **457 runs, 4409 assertions, 35 failures, 30 errors**. All 65 failing identities already occur in the preceding integrated baseline; none are new. The existing TickRunner lock-stub test is among these baseline failures and is not represented as passing. The focused green suite includes actual tick lifecycle, scheduling and watchdog checks.

Terminating Rails/Tailwind asset precompile passed; existing Browserslist freshness warning retained. Google Chrome **155.0.8059.41**, verified official installed binary, was the only browser used. Celestial-only preview at a stopped post-activation tick: all three systems, reload and actual process restart retain identical phase/anchor; 85 actual rendered mesh positions agree with server XYZ and version. No Chrome console errors were observed. Logs and detailed operator identity/travel evidence remain in ignored local files.

Representative unwrapped rates, independently checked against pre-release actual-tick positions (principal angles alone omit complete turns):

| System/body | Previous degrees/tick | Corrected degrees/tick | Previous ticks/orbit | Corrected ticks/orbit |
| --- | ---: | ---: | ---: | ---: |
| Pyro / Pyro I | 480.862614 | 4.808626 | 0.748655 | 74.865458 |
| Nyx / Nyx I | 1236.893806 | 12.368938 | 0.291052 | 29.105166 |
| Stanton / Hurston | 269.328164 | 2.693282 | 1.336659 | 133.665932 |

These are circular-orbit angular periods, not chord-distance ratios or travel durations. Actual production sampling captured every tick from 696770 through 696789, including activation at 696781 and eight consecutive slow intervals. Each interval advances 6048 orbital seconds. The measured angular ratios are 0.01 within numerical tolerance; periods in ticks increase 100-fold. The pre-release principal-angle deltas for Pyro I and Nyx I were 120.862614 and 156.893806 degrees: the independently known periods establish the additional one and three complete turns respectively. No chord-distance scaling is used. Chrome mesh coordinates at actual ticks 696782, 696785 and 696789 independently reproduce the corrected rates above.

## Release and phase-safe rollback procedure

Prepare a new version without editing the old catalog:

```bash
bin/codex_exec ruby script/orbital_progression.rb \
  --source config/orbital_calibrations/v2.yml \
  --output config/orbital_calibrations/v3.yml --version orbital-v3 \
  --current-tick CURRENT --activation-tick FUTURE --multiplier 0.01
```

The generator refuses overwrites, past/current activation, duplicate/reordered schedule ticks and invalid rates. Validate app/domain/database identity and baseline release again; cache v166 positions at the future activation tick; integrate the exact tested candidate through a normal PR and deploy that SHA using the established Heroku Git route. Verify both processes and new assets **before A**. If the release cannot be ready before A, prepare and qualify a later activation while the old mapping is still active. Do not ship a retroactive anchor.

Before A, the previous source is phase-compatible. **After A, a plain rollback to v166 would discard elapsed slow progression and jump positions.** Historical rollback recipes in the earlier release documents must not be used after this activation. Reverse the rate with a compatible new release retaining `Orbital::Clock` and the entire schedule:

```bash
bin/codex_exec ruby script/orbital_progression.rb \
  --source config/orbital_calibrations/v3.yml \
  --output config/orbital_calibrations/v4.yml --version orbital-v4 \
  --current-tick CURRENT --activation-tick FUTURE_REVERSAL --multiplier 1.0
```

Point `Catalog::DEFAULT_PATH` at v4, update the shipping-catalog test expectation to the reviewed append-only schedule, run the focused tests (including the reversal boundary), qualify assets/Chrome, integrate and deploy the exact reviewed SHA before the reversal tick. At R, inherited orbital seconds are `604800*A + 6048*(R-A)`; only the subsequent slope returns to 604800. The tested append-only schedule preserves every earlier position and is continuous at R. Validate fixed-tick positions around R, shared version/anchor, quotes, process identity and saved journeys, then observe actual ticks. If other application code must be reverted, retain this clock reader and complete schedule in the rollback candidate. Never restore the database or recalculate saved journeys to reverse this rate.

Production qualification requires actual ticks around A, independent server/map/quote comparison, Chrome measurements across all three systems, and at least 15 minutes of bounded health/travel-state observation after activation. Do not treat a successful push as completion.


## Production activation evidence

PR #27 integrated source `682cb21c78344b9ff9b4aba3a8160006207f6d2f`; the integrated tree is identical to the qualified feature candidate and the focused suite passed again on that exact SHA. A fresh authenticated preflight verified the app/domain/database binding, previous release, both processes and saved journeys before deployment. Heroku Git deployed that exact SHA as **v167**; authenticated release/slug metadata and both running web/worker processes confirmed it before activation. No schema, data, setting, ship or journey mutation was part of the release.

New page-referenced controller asset `d1831862d3651fca03a52b2db5766b9e74d25ccfa16e7238c8b0185e47894f4c` is served live. The server and browser consumed v3 before activation with rate 1, then changed to 0.01 at tick **696781** without a reload. Cached v166 positions at A-1 and A exactly match v167 for all 216 locations (432 comparisons). Independent Python propagation checks 648 positions at three fixed ticks around the boundary; all locations remain available, including every moon and station. Twelve live safe quotes match independently composed Gm coordinates; cross-system, unknown-location and stale-version requests retain their expected errors.

Chrome actual meshes agree with same-tick/version server XYZ in 300 comparisons across 18 snapshots, covering all three systems before/after activation and reload/reconnect. No Chrome console errors were observed. A fresh production one-off process read the identical persisted catalog/anchor, validated all 96 identities and all 216 positions, and reported 0.01 with 6048 orbital seconds/tick. A reversal rehearsal generated from the actual deployed catalog retained 864 positions across four historical/boundary checkpoints and restored rate 1 continuously; that rehearsal was not deployed.

The post-activation read-only aggregate audit retained all five saved paused-sentinel journeys byte-for-byte. There were no ordinary active journeys to observe arriving. Actual travel creation, arrival/lifecycle, interdiction/resume, minimum/ceiling, gateway timing and broker routing are qualified in isolated tests; production probes use safe quotes and read-only state rather than creating player journeys or processing arrivals.

Observation completed after **16 minutes 10 seconds**, from activation tick 696781 through tick 696844 (**63 tick advances**). Seven post-activation bounded health samples (nine total) contain no HTTP 5xx, infrastructure error codes or process crashes. Final authenticated release/app/domain/database verification confirms v167, exact source SHA and both processes up. Final independent positions, twelve corrected-position quotes, expected errors and assets pass again. All five saved paused-sentinel records remain unchanged. Production settings remain 15 real seconds and 168 global simulation hours per tick; the existing positive ship speeds remain 2 Gm/tick, with the same one invalid speed retained.

At the original observation closeout, Chrome's connection was unavailable for the optional last browser rerun; the completed earlier qualification and final HTTP/database checks were retained. The subsequent final production Chrome recheck below completes that deferred check. No other browser was used. The temporary preview server remains stopped.

Exact operational identities, timestamps, aggregate fingerprints, safe health summaries and detailed measurements are retained in ignored local operator evidence (`tmp/orbital-rate-closeout.json` and related files); no credentials or player payload logs are published. This closeout changes documentation only and is not redeployed: the running application source remains `682cb21c78344b9ff9b4aba3a8160006207f6d2f`.


## Final production Chrome recheck — 23 October 2026 (Pacific)

The deferred final Chrome check is complete. A fresh authenticated app/domain/database/release audit still confirms **v167**, exact running source `682cb21c78344b9ff9b4aba3a8160006207f6d2f`, and both web/worker processes up. This is a documentation-only follow-up; no application deployment or production mutation was needed.

The installed **Google Chrome 155.0.8059.41** binary was verified again and was the only browser used. A fresh live page followed actual tick broadcasts in Stanton, Pyro and Nyx, then reloaded/reconnected and revisited all three systems. Every snapshot retains catalog `orbital-v3:cfc59e789927b6af`, multiplier **0.01**, activation tick **696781**, inherited orbital seconds **421413148800**, and an effective advance of **6048 orbital seconds/tick**. The original anchor remains intact hundreds of ticks after activation.

| System/body | Actual Chrome ticks measured | Measured degrees/tick | Ticks/orbit |
| --- | --- | ---: | ---: |
| Pyro / Pyro I | 697355, 697358, 697361 | 4.808626 | 74.865458 |
| Nyx / Nyx I | 697355, 697358, 697362 | 12.368938 | 29.105166 |
| Stanton / Hurston | 697355, 697358, 697361 | 2.693282 | 133.665932 |

These angular measurements use actual rendered mesh coordinates and tick differences. Each measured interval is shorter than a complete corrected orbit, avoiding full-turn aliasing; chord lengths are not used. The rates reproduce the prior independently established 0.01 angular ratio and 100-fold periods.

**170 actual rendered mesh positions across 12 snapshots and six distinct ticks** agree with server XYZ and orbital clock metadata at the same tick/version. This includes neighbourhood views at ticks 697366–697367: Arial remains 0.0300 Gm from Hurston, Everus Harbor 0.0014 Gm from Hurston, Vuur 0.3800 Gm from Pyro V, and People's Service Station Lambda 30.0000 Gm from Nyx. No Chrome console errors were observed. A viewport screenshot of the live Hurston neighbourhood was saved locally as `orbital-rate-final-production-recheck.png`.

Independent safe HTTP checks pass again for all 216 locations around the activation boundary, twelve current-position quotes, expected error responses and the served asset. The five saved paused-sentinel journeys still match the original release audit. The bounded infrastructure sample contains no HTTP 5xx or process crashes. It does include one **H27 / Client Request Interrupted** on `GET /locations` with status 200; replacement snapshots loaded and passed comparison. This is consistent with the renderer cancelling a superseded request during navigation/reload. It is retained here rather than claiming that every router error code was absent.

Detailed recheck data, measurements, identity verification and health/travel audit remain in ignored local `tmp/orbital-rate-chrome-recheck-*` evidence. The original test/build results and 16m10s observation above remain historical qualification evidence. The final Chrome limitation is resolved; the running release and phase-safe rollback procedure are unchanged.
