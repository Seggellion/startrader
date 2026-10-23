# Moon and station calibration

23 October 2026. Follow-up to the primary orbital calibration. Implementation, production activation and observation complete; see the completion record below.

## Model and coverage

`config/orbital_calibrations/v2.yml` extends the documented simulation parameters authorized for this project. These are explicit simulation choices, not measured game ephemerides. It contains **96 protected composite identities**: the previous 18 plus **18 moons and 60 stations** in Stanton, Pyro and Nyx. The fresh celestial-only production inventory has 216 locations; every location resolves under this model, including cities/outposts inheriting their host centers.

The original catalog remains immutable. All 14 primary target radii, stellar masses, primary phases and anchored clock are unchanged. Independent comparisons with v1 at ticks 0, 10 and 700000 show identical primary world positions. New effective planetary masses supply central gravity for local orbits without changing the planet's own orbit around its star.

Moons and ordinary stations have explicit circular host-relative radii and phases at the existing epoch. World XYZ is composed recursively: star → planet → moon → station. Positive local distances are never replaced by zero or by placeholder imported values. Surface cities/outposts retain the documented host-center approximation. Unknown future identities remain unavailable until calibrated.

| Local system | Moon: radius Gm / phase degrees |
| --- | --- |
| Hurston | Arial .03/15; Aberdeen .05/110; Ita .08/215; Magda .12/305 |
| Crusader | Cellin .08/30; Daymar .07/155; Yela .05/270 |
| ArcCorp | Lyria .08/55; Wala .20/235 |
| MicroTech | Calliope .08/10; Clio .12/140; Euterpe .20/265 |
| Pyro V | Ignis .13/25; Vatra .10/85; Adir .18/145; Fairo .24/205; Fuego .30/265; Vuur .38/325 |

Explicit simulation masses: Crusader/Pyro V 1.9e27 kg; Pyro IV 6e26 kg; Delamar 6e22 kg; remaining planets 6e25 kg; moons 7.35e22 kg. All station radii/phases are enumerated in the catalog, including the star-orbiting stations and gateways. Station self-mass is unnecessary for test-particle orbital propagation and is not inferred from imported `500` placeholders.

Lagrange-named stations use **Lagrange-inspired coorbital placement**, not an exact three-body equilibrium. Their catalog parent remains the planet. L1/L2 use .98/1.02 times that planet's star-relative vector. L3 rotates the vector 180 degrees; L4/L5 rotate +60/-60 degrees. They share the host's angular evolution, avoiding an independent local orbit that would drift away from the intended placement.

Imported orbital fields remain reference data. Calibration takes precedence over moon/station imports and raw edits, with guarded identities/parents. The station importer now treats blank parent names as absent. No schema, persisted orbital field, speed, tick setting or saved journey update is required.

## Position, travel and interface

The shared snapshot reports both star-centered physical XYZ and parent-relative XYZ/distance, parent position and orbit model. API serializers identify Kepler versus coorbital models explicitly. `GrimHEX` resolves to the existing Green Imperial Housing Exchange station on Yela. Cross-system direct travel still rejects independent frames; gateway transfer timing remains unchanged.

Ship speed retains its Gm/tick meaning. Ceiling, the ordinary two-tick minimum, pause/interdiction behavior, saved journeys and RabbitMQ routing remain unchanged. Examples: Hurston–Arial .03 Gm, Yela–GrimHEX .001 Gm, Hurston–Everus Harbor .0014 Gm, Hurston–HUR-L1 .26 Gm, Hurston–HUR-L4 13 Gm. At speed 2 these first four short routes still use the two-tick ordinary minimum.

The map adds an **Orbital view** selector for each calibrated planet, moon and station. System overview retains physical scale and declutters station labels. Local views show the host and its children, with explicit host-relative labels and camera clipping ranges suited to small orbits. Station views include their host and center the camera there. Rings are centered on their actual parent. Presentation marker sizing and camera movement do not alter world positions, quoted distance or duration. Dense views suppress overlapping labels; selecting a station shows its own details. The camera follows a moving host across ticks while retaining user zoom.

## Qualification

- Relevant isolated suite: **161 tests / 1778 assertions**, zero failures/errors/skips. Includes all 78 new bodies at multiple ticks, independent nested offsets, coorbital geometry, unchanged primaries/clock, mass validation, missing parents, actual moon/station reimports, quotes and an actual new moon-to-station travel request with the ordinary minimum and dev broker routing.
- Broader suite: **447 runs / 2841 assertions, 35 failures / 30 errors**. Same 65 failing test identities as the previous qualified source; no newly failing identities. These existing legacy failures are not claimed as passing.
- Terminating Rails/Tailwind asset precompile passed. Google Chrome **155.0.8059.41**, verified installed Google Chrome binary, used exclusively. Checked Hurston moons, moon-hosted GrimHEX, dense Pyro V moons/stations, Nyx star-orbiting stations, system switching, stopped preview clock and console errors. A tiny-orbit camera near-plane clipping issue found during inspection was fixed before activation.
- Read-only full production celestial inventory validates 96 catalog identities and all 216 positions at a fixed tick. No production travel mutation is a verification probe.

## Release and recovery

Deploy the exact integrated source after verifying the current app/domain/database/release binding. The catalog, server metadata and digested renderer activate together. Clients handle catalog version changes; a full reload loads the new selector and renderer. There are no database activation commands. Revert to the previous compatible application release to restore v1 behavior; do not recompute saved journeys or restore a database for this code-only change.

Operational app/database/release identifiers and saved-journey fingerprints are retained in ignored local operator evidence. Public closeout records qualification and nonidentifying results only.

## Completion record

PR #25 integrated the qualified implementation as `782b2fe3b5faa3f8432f17b7f241163ed6f69da3`. The exact deployed source/catalog and both running processes were verified through authenticated release metadata. No database changes were made.

Final live verification independently reproduced all **216 positions** at fixed tick 700000 using a separate Python implementation, including all **18 moons and 60 stations**. Nine safe live quotes, expected cross-system/unknown/version errors, effective units and fresh page-referenced source assets passed. The pure deployed diagnostic independently validated all 96 identities and zero unavailable positions; Yela–GrimHEX measured .001 Gm and retained the two-tick ordinary minimum.

Google Chrome verified all three systems, Hurston's moons, Pyro V's moons/stations, a moon-hosted station, Nyx star stations, local host tracking across live ticks, a fresh page/reconnection, and zoom-independent distances. Console checks were empty. The new Orbital view selector exposes close views without changing physical coordinates. A live screenshot is retained locally; the temporary preview server is stopped.

The required observation lasted **15 minutes 21 seconds**, with **61 ticks** of progress and **six bounded infrastructure health samples**. No server HTTP5xx or process crashes appeared in those samples. One H27 client-interrupted `/locations` request was recorded during view switching; its replacement snapshot loaded normally. This is consistent with the renderer aborting a superseded fetch; [Heroku describes H27 as client interruption](https://help.heroku.com/VX2J01DE/why-do-h27-errors-happen). This bounded evidence is not a claim of indefinite monitoring or complete application-log coverage. Existing saved-journey state remained unchanged throughout.

Detailed operational identifiers, exact observation timestamps, aggregate fingerprints and rollback commands remain in the ignored local operator record `tmp/orbital-nested-operator-record.md`, with machine evidence in `tmp/orbital-nested-closeout.json`, `tmp/orbital-nested-live-results.json` and `tmp/orbital-nested-health.jsonl`. They are not public repository artifacts. This final closeout changes documentation only; the verified running application source remains the implementation SHA above.

Retained approximation: local orbital elements/masses/phases are documented simulation choices, Lagrange placement is a coorbital approximation, and surface sites use host centers. The broader legacy failures documented above remain unresolved by this scoped calibration.
