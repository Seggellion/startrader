# Orbital progression correction

23 October 2026. Candidate qualification complete; production activation and observation pending. This document supplements the historical calibration and nested-orbit release evidence.

## Diagnosis and implementation

Authenticated production revalidation found release v166, source `782b2fe3b5faa3f8432f17b7f241163ed6f69da3`, catalog `orbital-v2:bbe91ae886034b0c`, with both web and worker running. Fresh celestial payloads and actual tick samples match that source. No duplicate orbital advancement or seconds conversion defect was found. TickJob/TickRunner increment the shared tick under existing locks; the browser fetches server positions and renders them without propagating time. The previous orbital mapping advances 604800 seconds per tick, producing multiple revolutions for some inner bodies.

`Orbital::Clock` now owns the single `orbital_progression_multiplier`. The immutable, content-versioned v3 catalog carries an ordered activation schedule. Activation is scheduled at tick **696781**, with inherited orbital seconds **421413148800**. Global `simulation_seconds` and the base `simulated_seconds_per_tick=604800` remain unchanged. Only `orbital_seconds` passed to Kepler propagation changes. At activation tick A, orbital seconds equal the old mapping exactly; subsequent ticks advance by `604800 × 0.01 = 6048` orbital seconds. The slope of the first interval after A is reduced, while the position at A remains continuous. Historical ticks retain their previous positions.

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

These are circular-orbit angular periods, not chord-distance ratios or travel durations. Post-release measurements and the exact activation/catalog/release SHA will be recorded after production verification.

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

Point `Catalog::DEFAULT_PATH` at v4, run the focused tests (including the reversal boundary), qualify assets/Chrome, integrate and deploy the exact reviewed SHA before the reversal tick. At R, inherited orbital seconds are `604800*A + 6048*(R-A)`; only the subsequent slope returns to 604800. The tested append-only schedule preserves every earlier position and is continuous at R. Validate fixed-tick positions around R, shared version/anchor, quotes, process identity and saved journeys, then observe actual ticks. If other application code must be reverted, retain this clock reader and complete schedule in the rollback candidate. Never restore the database or recalculate saved journeys to reverse this rate.

Production qualification requires actual ticks around A, independent server/map/quote comparison, Chrome measurements across all three systems, and at least 15 minutes of bounded health/travel-state observation after activation. Do not treat a successful push as completion.
