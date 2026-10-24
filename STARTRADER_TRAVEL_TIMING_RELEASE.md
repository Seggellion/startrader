# Travel timing calibration

24 October 2026 (America/Vancouver). Candidate qualified; production integration and verification pending. This follows the completed orbital calibration, 0.01 orbital slowdown and final Chrome recheck.

## Audit and correction

Fresh authenticated production revalidation found v167 at source `682cb21c78344b9ff9b4aba3a8160006207f6d2f`, with the verified app/domain/database binding and both web/worker up. The persisted settings are 15 real seconds/tick and 168 global simulation hours/tick. One healthy TickJob chain is queued. Ship reference records contain 241 speeds of 2 and one NULL. No current fivefold scene-scale conversion remains; the old ordinary calculator divided physical distance by that raw field, so a 30 Gm journey at speed 2 took 15 ticks: this did not meet the requested contract.

`TravelTiming::SPEED_GM_PER_TICK = 1.0` is now the authoritative ordinary rate for every ship. `duration_ticks` applies **max(ceil(physical_distance_Gm / 1.0), 2)**. `TravelTimeCalculator` and the non-mutating distance API share it. Imported/raw `Ship#speed` remains reference metadata, explicitly labelled in the admin form, and cannot alter ordinary duration. No ship-specific travel rates are retained. Tests cover NULL, zero, negative, 2 and 100 reference values, newly imported ships with no speed, reimports and raw speed edits. The UEX and StarBitizen importers do not populate this field; ship sync resolves existing records and does not convert speeds. The database column has no default. No bulk ship data update is required or performed.

TravelService captures one read-only departure tick for availability validation, physical distance and persisted departure/arrival. Ordinary distance is the composed star-centered physical Gm snapshot, independent of camera scale or orbital seconds. New travel responses capture one response tick for the countdown and include the saved departure and additive effective-rate/duration metadata. Distance responses add effective Gm/tick, duration ticks, real seconds/tick and nominal seconds without removing existing fields.

The production real-time setting already equals 15. The previous missing/invalid-setting fallback was 1 second; it is now 15, with non-finite values also rejected. TickJob still reschedules using `Tick.seconds_per_tick.seconds` and the existing locks/watchdog. Remaining seconds use saved arrival minus current tick, multiplied by real seconds/tick. No scheduling seconds are taken from the orbital clock. The worker schedules its next tick 15 real seconds after completion; nominal durations exclude execution/queue latency.

No orbital source, catalog, phases, radii, masses, parent graph, units or browser progression code changes. Catalog remains `orbital-v3:cfc59e789927b6af`, multiplier 0.01, activation tick 696781 with orbital seconds 421413148800. All saved journeys keep their departure, arrival, duration, paused sentinel and RabbitMQ environment. Existing gateway timing remains `ceil(120 / real_seconds_per_tick)`, eight ticks at 15 seconds. No schema, setting, ship, location or journey mutation is part of this release.

## Deterministic qualification

**210 focused tests / 4247 assertions pass**, with zero failures/errors/skips. The isolated PostgreSQL test database is separate from production and uses a non-superuser role; real broker connections are prohibited.

The new pipeline tests construct controlled circular-orbit physical fixtures, create travel through the normal TravelService, and execute real queued TickJobs through Delayed::Worker under controlled time. This traverses **TickJob → TickRunner → Tick.increment! → ShipArrivalJob → ShipTravelArrivalProcessor → real RabbitmqSender with an in-memory channel**. Arrival dispatch/processors and geometry are not stubbed. Only external connections/notifications and unrelated market-price broadcasts are replaced. No final-tick assignment, direct arrival shortcut, wall-clock sleeps, or production clock acceleration is used.

For the synthetic 30 Gm fixture, departure is T=1000, duration 30, arrival T+30. At T+29 the ship is still in transit at its origin and no arrival publication exists. At T+30 it reaches the destination, updates player location, cleans up its travel and publishes exactly once to the saved environment. T+31 produces no duplicate. Every actual queued reschedule is asserted at exactly 15 controlled seconds; virtual arrival time is 450 seconds. The 28 and 36 Gm cases exercise the same complete dispatch path.

| Synthetic physical fixture | Ticks | Nominal real time |
| --- | ---: | --- |
| 28 Gm | 28 | 7m00s |
| 30 Gm | 30 | 7m30s |
| 36 Gm | 36 | 9m00s |

Additional tests cover fractional ceiling boundaries, the two-tick minimum, tick-boundary departure capture, import/reference-speed independence, real-tick paused/interdicted sentinel retention and resume, and a pre-existing 15-tick journey arriving on its saved schedule rather than being recalculated to 30. Existing gateway and environment-routing regressions pass. Five older arrival tests had incomplete ship fixtures lacking their shard; supplying the real shard relationship restores those tests without modifying production arrival behavior.

Broader suite: **468 runs / 5247 assertions, 34 failures and 26 errors**. All 60 failing identities are pre-existing; comparison with the preceding 65-identity baseline finds no new failing identities and resolves the five arrival fixture failures above. Legacy admin authentication/routes/trading fixture failures remain. This is not a globally green suite.

The terminating Rails/Tailwind asset build passes, retaining the existing Browserslist freshness warning. The actual admin form renders the effective 1.0 Gm/tick explanation and legacy-speed label. `git diff --check` passes. Orbital files/catalogs and browser progression source are byte-for-byte unchanged.

## Actual route samples

These are actual celestial routes at fixed tick **701104**, catalog **orbital-v3:cfc59e789927b6af**, using candidate ordinary rate **1 Gm/tick** and real step **15 seconds**. The pure audit's composed positions were independently compared with current production server snapshots at that same tick/version. They are not synthetic 30 Gm fixtures or historical live travel departures.

| System / route | Physical Gm | Effective Gm/tick | Ticks | Nominal real time |
| --- | ---: | ---: | ---: | --- |
| Pyro I → Monox | 8.215865259 | 1 | 9 | 2m15s |
| Pyro IV → Pyro V | 95.200000000 | 1 | 96 | 24m00s |
| Nyx I → Nyx II | 25.631551398 | 1 | 26 | 6m30s |
| Hurston → Crusader | 28.754349576 | 1 | 29 | 7m15s |
| Hurston → Arial | 0.030000000 | 1 | 2 | 0m30s |

Only separations around 28–36 Gm imply approximately 7–9 nominal minutes. Shorter/longer routes above reflect their actual separation and the short-trip minimum; geometry is not adjusted to force durations into that range. `script/travel_timing_audit.rb` reads a repeatable-read, read-only database snapshot or supplied celestial JSON, captures one tick and uses the same Orbital::Snapshot and TravelTiming policy without booting Rails, brokers or jobs.

## Integration, production checks and rollback

Integrate a qualified exact SHA through the normal PR process, recheck app/domain/database and v167 immediately before deployment, record saved-travel state, and deploy the exact integrated SHA through the established Heroku Git route. No database command or migration is needed. Verify the release/slug and both processes, new quote metadata/calculations, retained orbital anchor/version, read-only journey state and bounded infrastructure health. Use Google Chrome only for browser checks. Prove arrival timing in the isolated deterministic tests, never with test journeys, artificial ticks, sleep loops or an accelerated production clock. The explicit current request supersedes earlier orbital-release waiting procedures: this qualification uses deterministic scheduling and bounded live checks without waiting 7–10 minutes for travel.

Rollback is source-only to the recorded v167 release, after confirming the real persisted tick setting is still 15. Both source versions read the identical v3 orbital schedule, so phase and its activation anchor remain coherent. New journeys created under the correction retain their saved longer arrivals even if the old source is restored; resumed journeys retain saved remaining ticks. Do not recompute existing durations, clear queues, reset ticks, restore the database or apply the earlier orbital rate reversal. Rolling back ordinary travel restores the prior calculator for future departures only. Verify slug/process identity, same-tick orbital coordinates and saved journey state afterward.

Production release/SHA and verification results will be appended after deployment. Detailed operational identities, aggregate journey fingerprints and local test/audit logs remain in ignored operator evidence.
