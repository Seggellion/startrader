# StarTrader orbital calibration discovery

Date: 23 October 2026 (America/Vancouver). Owner: Dustin Hill.

Scope: M0 discovery only. Companion: [implementation playbook](STARTRADER_ORBITAL_CALIBRATION_PLAYBOOK.md).

## Result and limits

All 14 requested targets have identifiable records in the public StarTrader celestial payload. Levski is a city on Delamar; its target should be applied to that host if the intended quantity is a star-relative radius. Pyro IV and Pyro V are separate, star-parented planets in the current data. Their equal requested radii provide no evidence of equal positions.

Changing orbital numbers alone will not fix travel calculations. The server feeds scaled scene coordinates into distance and duration calculations; the browser independently computes positions with different mass and clock interpretations and ignores parent transforms. Several importers overwrite manually calibrated values with constants. A second distance helper subtracts periapsides.

Follow-up direction from Dustin on 23 October 2026: the supplied Gm values are star-distance **calibration targets for the existing orbital calculator**, and the presentation should remain practical and comparable to current Stanton. Stellar-mass adjustment is explicitly in scope. This supersedes the initial static-snapshot recommendation below: retain and correct the existing orbital model rather than replace it with static positions by default. Mass alone cannot satisfy these targets under the current equations; orbital-distance parameters and rendering scale require separate calibration.

Discovery is delivered with explicit evidence gaps. Production release identity, database identifiers beyond public location primary keys, actual tick settings, catalog speed values, and existing travel state could not be verified because database and Heroku authentication were unavailable. Baselines below are **local source replays of public celestial data**, not observed production quotes. No application code, database data, imports, migrations, travel, deployment, or Git refs were changed. No browser tests were run.

## Checkout and evidence classification

| Item | Evidence |
| --- | --- |
| Checkout | `/home/dusti/startrader`, exposed as `\\wsl.localhost\Ubuntu\home\dusti\startrader` |
| Inspected commit | `fecb49f619bf69eeeef9beb50a037dc7a95469a7` |
| Branch | `main`; locally cached `origin/main` and `heroku/main` point to the same commit; no fetch performed |
| Origin | `https://github.com/Seggellion/startrader.git` |
| Heroku remote | `https://git.heroku.com/star-trader.git`; **candidate app `star-trader`, not the brief's unverified `startrader-production`** |
| Initial Linux Git state | Only unrelated untracked `.claude/`; preserved |
| Existing worktree | `.claude/worktrees/friendly-leakey-963229`, branch `claude/friendly-leakey-963229`, same HEAD; left alone |
| Applicable instructions | User-supplied AGENTS.md: Google Chrome only for browser testing, including release qualification. No on-disk AGENTS.md found at the checked ancestors or under `app`, `config`, `db`, `lib`, `test`, `bin` |
| Documentation convention | Only tracked Markdown outside dependencies is root `README.md`; these two reports therefore live at repository root |

Use Linux Git inside WSL. Windows Git against the UNC checkout reported spurious symlink/mode and `Zone.Identifier` changes and a `Function not implemented` error; those are not the Linux working-tree baseline. An initial overly broad parent-directory instruction search was superseded by bounded ancestor/source searches; it is not evidence about other projects.

Evidence labels used here:

- **Repository:** source at the exact commit above; citations are repository-relative path and one-based lines.
- **Runtime:** public HTTP responses from the named host on 23 October 2026. The deployed SHA is unknown, so source/runtime agreement is an inference.
- **Replay:** existing Ruby calculation source executed without Rails, DB access, or application initializers, with lightweight location adapters and explicit synthetic settings.
- **Requirement:** the user's Gm numbers; not independently verified game ephemerides.
- **Proposal / unresolved:** a future contract or implementation choice, not current behavior.

## Framework, entry points, and sources of truth

The lockfile selects Rails 8.0.1, pg 1.5.9, Turbo Rails 2.0.11, Stimulus Rails 1.3.4, importmap-rails 2.1.0, Sprockets Rails 3.5.2, delayed_job_active_record 4.1.11, Capybara 3.40.0, Selenium 4.27.0. `Gemfile` and `.ruby-version` pin Ruby 3.2.2. `bin/codex_exec --ruby-diagnostics` successfully activated Ruby 3.2.2 and Bundler 2.4.22. Available clients: Node 18.19.1, psql 18.1, Heroku CLI 11.11.0. These do not establish production runtime versions or PostgreSQL server version.

`config/application.rb:12,20` loads Rails 8 defaults and Delayed Job. `config/importmap.rb:12-21` pins Three.js 0.161.0 and local orbital modules. `app/javascript/application.js:1-10` loads Turbo, Stimulus controllers, and channels. There is no npm test command or JavaScript bundling command in `package.json`; its CSS command uses `--watch` and is unsuitable as a terminating release check.

| Source / writer | Current behavior and precedence |
| --- | --- |
| `db/schema.rb:203-261` | `locations` has float `periapsis`, `apoapsis`, `mass`; string `parent_name`, `classification`, `star_system_name`; PK `id`, external `api_id` and typed `id_*` columns. No epoch, phase, inclination, period, eccentricity, XYZ, unit, or dataset-version columns. `name` is unique; `api_id` index is not unique. No parent FK enforces hierarchy. |
| `app/models/location.rb:2-15,79-85` | Parent association joins `parent_name` to **name**, not an ID; star lookup is by `star_system_name` against `name`. `stars` memoizes an `api_id` map at process scope. |
| `LocationsController#index`, `app/controllers/locations_controller.rb:9-54` | `/locations?star=...` reads Location fields live, selecting one star then planets/moons/stations/cities/outposts; emits PK IDs, parent names, orbital fields, star mass. No version or clock metadata. |
| `Api::LocationsController`, `app/controllers/api/locations_controller.rb:7-18,58-70,101-105` | GET inventory reads the same table; its legacy serializer omits `api_id`, nickname, code, and typed source IDs. Generic create/update methods can write orbital fields, although current routes expose only index/show (`config/routes.rb:110`). |
| `PlanetsImporter.import_location`, `app/services/admin/data/planets_importer.rb:62-85` | Matches by display name, assigns star parent, **mass 5.972e24, periapsis 147, apoapsis 152** every time. |
| `MoonsImporter.import_location`, `app/services/admin/data/moons_importer.rb:46-68` | Matches by name; planet parent; **mass 100, periapsis/apoapsis 70**. |
| `StationsImporter.import_location`, `app/services/admin/data/stations_importer.rb:73-97,180-183` | Matches by name; moon/planet/star parent; **mass 500, periapsis/apoapsis 200**. Empty strings are truthy in Ruby, so parent fallback using `||` needs normalization. |
| `StarSystemsImporter.import_location`, `app/services/admin/data/star_systems_importer.rb:65-93` | Matches external ID plus classification; writes **mass 166,500,000** and zero apsides. |
| `LocationsImporter.import_location`, `app/services/admin/data/locations_importer.rb:48-73,140-174` | Generic importer matches unqualified `api_id`, writes payload mass/apsides (including nil), and can place a numeric parent ID into `parent_name`, despite the name-based association. Cross-type external-ID collisions are possible. |
| Cities / outposts importers | `cities_importer.rb:76-102`, `outposts_importer.rb:76-104` use external ID plus classification, assign parent names, and overwrite apsides/mass from payload. |
| Admin controls | `app/controllers/admin/data_controller.rb:47-126` invokes the above importers, including raw station/system JSON. Planets, moons, stations, systems, cities, outposts admin edit actions permit orbital fields; e.g. `admin/planets_controller.rb:26-28,54-58`. Edits directly alter the runtime table. Forms do not explain units. |
| Terminal importer | `app/services/admin/data/terminals_importer.rb:309-400` resolves terminal hosts using typed external IDs and contextual names. It does not own orbital data. Preserve terminal and facility links when calibrating. |
| Seeds / fixtures / jobs | `db/seeds.rb:1-42` creates unrelated commodity data, not an orbital catalog. Existing orbital tests construct synthetic records; there is no `test/fixtures/locations.yml` or `ships.yml`. Source search found no orbital-update job or tick-time write of apsides. External/manual imports remain possible and unobserved. |
| Assets / caches | Source modules are importmapped; digested copies exist under `public/assets`. Edit source in later milestones and rebuild assets, never patch digests. Location orbital reads are not explicitly cached; `Location.stars` is memoized. Production HTTP assets have one-year cache headers (`production.rb:18-19`), requiring new digests and process restart for a release. |

There is no durable calibration precedence today: the last database writer wins. A post-deployment manual correction is vulnerable to replaying imports.

## Complete 14-row before/after inventory

Runtime source for this table: public `/locations?star=Pyro`, `Nyx`, `Stanton`. Values are stored apsides as serialized, **not instantaneous radial distances**. Units are inferred from both physics implementations' Mkm comments: 1 Mkm = 1 Gm. The HTTP payload itself has no unit declaration. No independent game data is substituted.

`id` below is an observed **Location primary key on this host**, not a UEX ID or a portable cross-environment identifier. `api_id`, nickname/code aliases, typed IDs, and parent identity uniqueness require the database audit in M1. Alias columns list charter mappings to establish, not proof that every input string currently resolves through the APIs.

| System | User target / aliases | Observed canonical name and PK | Class | Observed parent / derived parent PK | Current peri/apo (inferred Gm) | Proposed target (Gm) and governing source |
| --- | --- | --- | --- | --- | --- | --- |
| Pyro | Pyro 1 / Pyro I | Pyro I `1015` | planet | Pyro `1510` | 147 / 152 | **8.2**, charter; versioned calibration proposed |
| Pyro | Monox / Pyro 2 | Monox `1016` | planet | Pyro `1510` | 147 / 152 | **10.6**, charter; alias confirmation pending |
| Pyro | Bloom / Pyro 3 | Bloom `1017` | planet | Pyro `1510` | 147 / 152 | **17.8**, charter; alias confirmation pending |
| Pyro | Pyro 4 / P4 | Pyro IV `338` | planet | Pyro `1510` | 147 / 152 | **47.6**, charter; hierarchy/phase decision required |
| Pyro | Pyro 5 / P5 | Pyro V `1018` | planet | Pyro `1510` | 147 / 152 | **47.6**, charter; distinct body; no coordinate copying |
| Pyro | Terminus / Pyro 6 | Terminus `1019` | planet | Pyro `1510` | 147 / 152 | **68.0**, charter; alias confirmation pending |
| Nyx | Nyx 1 / Nyx I | Nyx I `979` | planet | Nyx `1501` | 147 / 152 | **5.0**, charter |
| Nyx | Nyx 2 / Nyx II | Nyx II `980` | planet | Nyx `1501` | 147 / 152 | **25.0**, charter |
| Nyx | Levski | Levski `1190`; host Delamar `1099` | city; host planet | Delamar `1099`; host parent Nyx `1501` | Levski nil / nil; host 147 / 152 | **15.0** on host Delamar proposed; preserve city inheritance/local offset |
| Nyx | Nyx 3 / Nyx III | Nyx III `981` | planet | Nyx `1501` | 147 / 152 | **48.0**, charter |
| Stanton | Crusader | Crusader `834` | planet | Stanton `1256` | 100 / 100 | **20.0**, charter |
| Stanton | Hurston | Hurston `891` | planet | Stanton `1256` | 60 / 60 | **13.0**, charter |
| Stanton | microTech | **MicroTech** `965` | planet | Stanton `1256` | 210 / 210 | **42.0**, charter; preserve existing canonical spelling |
| Stanton | ArcCorp | ArcCorp `1366` | planet | Stanton `1256` | 147 / 151 | **30.0**, charter |

Current governing source for all rows is the Location table, subject to the writers above. No proposed values have been applied. If the targets are fixed circular radii, both effective apsides equal the target; if they are reference-epoch distances, assigning both apsides is unjustified. That choice is pending.

The map returned 75 Pyro, 12 Nyx, and 129 Stanton records, including one selected star per system. Separate public `/api/locations?system=...` reads returned the same respective counts. There were no duplicate exact names in those responses, no missing named parent within each map payload, and no missing target row. These checks do **not** prove absence of duplicate `api_id`, normalized aliases, additional star rows excluded by the map, cycles, or corrupt typed relationships. Source schema permits several such problems; M1 must inspect them directly.

The payload's three stars each have mass `166500000.0`. Several moons have nil apsides/mass (e.g. Lyria, Adir); existing calculations can fail rather than return a valid position. Other local moon radii are implausibly large under the inferred unit contract; this project must not present arbitrary nested-route fidelity as established merely by fixing the 14 primary radii.

## Coordinate, orbit, and clock audit

### Server

`PlanetPositionCalculator`, `app/services/planet_position_calculator.rb`:

- Star origins are `(0,0)` per system (`21-25`). All implemented geometry is planar XY, with implicit `z=0`; there are no inclination/ascending-node/orientation transforms.
- Planets derive `a=(periapsis+apoapsis)/2`, `e=(apoapsis-periapsis)/(apoapsis+periapsis)` (`53-75`). These are radial apsides, not ellipse diameters. Semimajor axes and radii are in Mkm/Gm; mass is taken directly as kg.
- `G=6.67430e-38` is consistent with metres cubed converted to Gm cubed. Period is derived from radius and central mass (`3-4,47-49`). This is existing game approximation code, not validated ephemerides.
- Common periapsis epoch: Unix seconds for `2024-01-03T00:00:00Z`. Time input is `tick * Tick.simulated_seconds_per_tick`, then the Unix epoch is subtracted (`13,63-67,187-188`). Tick zero has no demonstrated real-world epoch mapping. No per-body phase input exists for planets/moons.
- Planets return **radius divided by `UNIT_SCALE=5`** (`9-10,72-75`). Moons add similarly scaled local XY to the parent planet's XY (`79-100`); only a simple planet→moon chain is supported, without recursive cycle validation.
- Cities/outposts inherit the parent center, with no modeled local offset; a missing parent returns the origin (`32-41`). Unsupported classifications also return origin (`42-43`). Nil orbital inputs otherwise cause arithmetic errors. These fallback origins must not be treated as known physical locations.
- Stations use name-selected heuristics: L1/L2 ±1% of parent position (`148-160`); co-orbitals rotate the entire parent vector using a final name digit (`163-172`); star-parented stations are circular and distributed by database ID among exact-orbit peers (`119-145`). Membership changes can change station phase. These are not surveyed station offsets.

`Location#distance_to`, `app/models/location.rb:48-56`, takes 2D Euclidean separation of those already scaled outputs. There is no conversion back to physical units and no same-frame/system guard in the method. It measures separation at the supplied departure tick, not an orbital arc, radius difference, or moving-destination interception.

### Browser

`star_system_controller.js:73-96` fetches `/locations` and sends all classifications to `CelestialBody`. IDs and parents are not carried into the animation records. `CelestialBody.js:26-29` treats masses below `1e20` as **solar masses**, multiplying by `1.98847e30`; Ruby treats the same `166500000` as kg. At identical orbital radii, this alone changes derived periods by roughly `sqrt(1.98847e30)`, about `1.41e15`.

`CelestialBody.js:12-16,62-94` sets linear position scale 5 and visual body scale/minimum sizes. `animation.js:250-263` calculates every body's star-centered position, including moons, stations, and cities with nonzero apsides. It does not compose their emitted parent relationships. Missing apsides omit a body from rendering. Bodies and labels are added directly to the scene.

`animation.js:76-115` calculates distances from mesh coordinates and labels them `GM`, so display scaling and `orbitPadding` contaminate the labeled values. The active map partial has no `#distances` container (`app/views/star_trader/_orbital_panel.html.erb:1-18`), so these lists currently have no visible target there. No active browser quote form or distance-calculator Stimulus controller was found; the public quote API still exists. Do not promise browser-form behavior that is absent from this checkout.

`CelestialBody.js:122-154` sizes the star and computes padding. It can affect rendered radii; there is no logarithmic scale found in this path. Body-size minimums and camera adjustments are separate display distortions. `animation.js:56` also computes an unused `_aScene` with a second division; the active rendering radius uses `_aRealMkm / unitScale` instead. `OrbitCreator.createOrbit` uses apsides as ellipse axes but is imported without an active invocation in the inspected path; it is not the calculator authority.

### Clocks and reproducibility

`Tick.seconds_per_tick` is real scheduling seconds (default 1); `Tick.simulated_seconds_per_tick` is `hours_per_tick * 3600` (default 3600), at `app/models/tick.rb:8-20`. TickChannel broadcasts only the former (`app/channels/tick_channel.rb:5-10`); the browser passes it to `useTickStep` as simulated seconds (`star_system_controller.js:45-65`). Thus defaults produce a 3600-fold time disagreement, independently of mass.

The active UI uses tick-step rendering, not RAF progression. Optional RAF/interpolation modes exist (`animation.js:123-243`), but are not invoked by the active controller. Tick-step is not inherently frame-rate dependent. However, initial tick/base setup precedes asynchronous data loading; `addPlanet` initializes phase relative to tick zero, while `onTick` adjusts existing bodies only on the first tick (`50-69,171-193`). A reload/system switch or tick arriving before bodies can change phase initialization. When stopped, status ignores the transmitted tick and renders local `simTime`. No shared data version is transmitted.

## Distance and travel request trace

1. Quote: `POST /api/distance_calculator` (`config/routes.rb:101`), body `{"distance":{"from":"Hurston","to":"Crusader"}}`.
2. `Api::DistanceCalculatorController#calculate`, `app/controllers/api/distance_calculator_controller.rb:8-29`, uses exact **display-name** lookups, returns 404 for missing names, and calls `Location#distance_to` at `Tick.current`. It reads the tick a second time for the response, permitting a boundary race. It has no unit, dataset version, IDs, alias disambiguation, frame check, or speed/duration field. It could subtract unrelated system-local origins.
3. Travel: `POST /api/travel`, body `ship_travel` fields, goes through `StarTraderShipSync`, may process due arrivals, initializes unknown locations, validates current ship location, then resolves destination in the current system (`app/controllers/api/ship_travel_controller.rb:10-106,448-459,601-704`). This is mutating, not a diagnostic quote.
4. `LocationResolver` uses exact/normalized names, nickname/code, facility suffixes, contextual system matches, and ranked matching (`app/services/location_resolver.rb:52-178,181-245`). Some scoped ambiguities raise errors; the unscoped exact path takes `.first`. There is no explicit charter alias table or guarantee that Arabic numerals/P4 resolve to Roman-named records. Calibration must resolve composite stable identities, not use its fuzzy search to mass-update data.
5. Normal travel rejects cross-system destinations (`ship_travel_controller.rb:74-76`); the quote endpoint lacks this protection. Same-endpoint travel is rejected, independently of zero geometry (`TravelService:23`).
6. `TravelService#call`, `app/services/travel_service.rb:30-55`, captures a start tick and invokes `TravelTimeCalculator`. That calculator returns `ceil(Location#distance_to / ship.speed)` (`travel_time_calculator.rb:10-16`). There is no acceleration/quantum/interception logic in this path. `ships.speed` is an integer without a documented unit (`db/schema.rb:493`); the effective present contract is scene units per tick. Ship admin UI labels it speed without resolving its physical meaning. Do not silently reinterpret it as km/s or Gm/s.
7. Service enforces minimum **2 ticks**, stores departure, arrival, duration, interdiction percentage, GUID, and RabbitMQ environment, then marks ship in transit. No physical distance, coordinates, epoch, or dataset version is persisted (`db/schema.rb:444-468`).
8. `ShipTravel#seconds_remaining` converts remaining ticks using real `Tick.seconds_per_tick`; interdiction windows use saved duration. Pausing stores remaining ticks and sets `arrival_tick=0`; resume uses that remainder with minimum 1 (`app/models/ship_travel.rb:68-115,134-161`). Calibration must not recompute existing trips or treat the zero sentinel as a fresh ordinary arrival.
9. Arrival processing changes location and publishes an arrival notification before lifecycle cleanup (`app/services/ship_travel_arrival_processor.rb:8-22`). Even `GET /api/location/:user_ship_id` can process arrivals (`ship_travel_controller.rb:123-129`). It was not used for discovery.
10. Intersystem travel has an explicit existing gateway service, not a physical interstellar distance: `GateTravelService`, `app/services/gate_travel_service.rb:2,44-55,118-146`, resolves paired gateways and uses `ceil(120 / real_seconds_per_tick)` ticks. Preserve it. Require quote errors for unsupported cross-frame direct routes.

Additional caller: `StarBitizenRun#distance`, `app/models/star_bitizen_run.rb:16-21`, returns absolute periapsis difference. No active view/caller of this helper was found in the source search; either migrate it to the same explicit contract with a clock or deprecate its distance claim. Do not leave a second purported physical-distance implementation.

## Baseline evidence

Public snapshots were fetched at 18:16:29–18:16:31 UTC on 23 October 2026 (11:16 PDT). Raw-response SHA-256 values, which identify observations rather than an application dataset version:

| Payload | SHA-256 |
| --- | --- |
| Pyro | `8cf564087f08fc3dba013ad9cd954828e7031a835a501681d8c23ea83a476aac` |
| Nyx | `2803357d9dec09733a2b2e1266c183715019d07706595e36ca9365ed742c7044` |
| Stanton | `2df47f0a102c686fdb9ff9d763b7f09cd62d5f3b037d4d3ebddd5a3a5bc8bc77` |

Replay loaded the **unchanged** `planet_position_calculator.rb`, `travel_time_calculator.rb`, and the exact `Location#distance_to` method from source lines 48–57. `OpenStruct` adapters supplied the public orbital fields and name-based parent/star lookup; a minimal Tick adapter supplied simulated seconds per tick. Rails and its initializers were not loaded. Clock: fixed tick **10**, simulated **3600 s/tick** (synthetic default assumption), existing periapsis epoch. Ship speed: synthetic **100 legacy scene units/tick**, not a live ship. Derived duration shows the actual calculator result and then the service's minimum rule; no travel record was created.

| Sample / IDs | A XY (legacy scene units) | B XY (legacy scene units) | Distance (legacy scene units) | Raw ticks → service minimum |
| --- | --- | --- | --- | --- |
| Pyro I `1015` → Monox `1016` | (29.4, -9.449394947182442e-8) | same | 0 | 0 → 2 |
| Nyx I `979` → Nyx II `980` | (29.4, -9.449394947182442e-8) | same | 0 | 0 → 2 |
| Hurston `891` → Crusader `834` | (11.999999999999998, -1.4668507769250222e-7) | (20, -1.13621774669176e-7) | 8.000000000000002 | 1 → 2 |
| Levski `1190` → Delamar `1099` | (29.4, -9.449394947182442e-8) | same | 0 | 0 → 2 |
| Pyro IV `338` → Pyro V `1018` | (29.4, -9.449394947182442e-8) | same | 0 | 0 → 2 |
| Hurston `891` → Arial `423` | (11.999999999999998, -1.4668507769250222e-7) | (2.0483745180899255, -0.9824207632226808) | 10 | 1 → 2 |

In this existing server model, multiplying each XY and distance by 5 recovers the Gm values implied by source comments. For example the Stanton sample is about 40 source-inferred Gm versus 8 scene units. This is a diagnosis of the old code, not a requirement to preserve its physical interpretation: Dustin's follow-up explicitly anchors the intended scale to current Stanton. This conversion does not validate the input orbits, masses, or angles. Zero Levski-host separation reflects the current body-center approximation; zero Pyro IV–V separation reflects duplicate orbital inputs and common phase, and is not supported as a game fact.

An additional isolated source probe set circular apsides 13 and 20 Gm and elapsed time exactly equal to `T_PERI_EPOCH_SEC`, producing `(2.6,0)` and `(4,0)` and a reported separation **1.4 scene units**. Independent arithmetic requires **7 Gm**. This confirms the scale boundary defect without relying on actual planetary alignment. The probe used a synthetic star mass `1.98847e30 kg` and a Tick adapter of 1 simulated second/tick; it is a separate fixture from the table.

No calibrated after-route numbers are asserted: phase/model decisions are pending. M3 must repeat these named routes at fixed clock/data version, report physical coordinates and derived durations, and explain each difference. Include a distinct equal-radius case with independently specified different angles, not just the existing coincident Pyro records.

### Follow-up feasibility: stellar mass and practical Stanton scale

The existing implementation fixes `a` and `e` from apsides before reading mass. Its equations are `T=2*pi*sqrt(a^3/(G*M))` and `r=a*(1-e^2)/(1+e*cos(nu))` (`planet_position_calculator.rb:47-75`). Changing mass changes period and therefore phase at a given tick. It cannot change a circular orbit's radius; for an ellipse it cannot move radius outside the existing periapsis/apoapsis interval. All six Pyro planets currently share 147–152 source-inferred Gm, so one stellar-mass change cannot spread them across targets 8.2–68 Gm. It also cannot move circular Crusader from 100 to 20 source-inferred Gm. Even under the old scene scale, its radius remains 20 scene units for every positive mass.

An isolated unchanged-source follow-up probe used circular apsides 100/100, tick 12,345, and synthetic 3600 simulated seconds/tick. Synthetic stellar masses `1e29`, `1e30`, and `1e31 kg` all returned **100 source-inferred Gm / 20 scene units**. Their periods were respectively about 76,908,972.0197, 24,320,752.4084, and 7,690,897.2020 seconds. These are illustrative test masses, not proposed production masses. No Rails or database was loaded.

| Stanton body | Existing unpadded scene radius/range | Requested physical target Gm |
| --- | --- | --- |
| Hurston | 12 | 13 |
| Crusader | 20 | 20 |
| MicroTech | 42 | 42 |
| ArcCorp | 29.4–30.2 | 30 |

This numerical agreement supports a practical rendering proposal: after calibrating physical radii to the supplied Gm values, use a nominal **1 scene unit per Gm** for these bodies. It keeps the current Stanton extent, with small intended Hurston/ArcCorp changes. It is a display mapping, not a redefinition of 1 Gm or justification to multiply the supplied targets by 5. Final camera fit/padding remains presentation-only and must be checked in Chrome.

Normalize stellar masses to explicit kg in both Ruby and JavaScript, remove the magnitude-based solar-mass guess, and protect authoritative mass values against the star-system/generic importers. A target radius alone does not determine a unique stellar mass in this model. A desired period plus semimajor axis would constrain it through `M=4*pi^2*a^3/(G*T^2)`; alternatively use a supported dated mass source or explicit approved simulation mass. Do not guess new production masses or fit three masses to 14 independently prescribed radii as if that were a solvable mass-only calibration. Resolve whether elliptical targets describe nominal distance, constant radius, or a fixed acceptance epoch before populating orbital fields.

## Diagnostics actually run and blocked evidence

The initial PowerShell reads of the attachment and root inventory succeeded. Sandboxed WSL startup returned `Wsl/E_ACCESSDENIED`; read-only WSL commands subsequently ran through the approved execution path. `rg` is unavailable inside WSL, so bounded `find`, `grep`, `nl`, and `sed` were used.

Representative executed commands (Bash inside WSL; source reads were batched):

```bash
cd /home/dusti/startrader
git status --short
git branch -vv
git rev-parse HEAD
git remote -v
git worktree list
git log -8 --format='%h %ad %s' --date=iso-strict
git show-ref
find app config db lib test bin -name AGENTS.md -print
git ls-files '*.md' '.github/*' 'app.json' 'heroku.yml' '*deploy*'
nl -ba app/services/planet_position_calculator.rb
nl -ba app/models/location.rb
nl -ba app/services/travel_service.rb
nl -ba app/services/travel_time_calculator.rb
pg_isready
bin/codex_exec --ruby-diagnostics
psql --version
node --version
PGOPTIONS='-c default_transaction_read_only=on' psql -X -w \
  -d star_trader_development -c 'SELECT current_database(), current_user;'
sudo -n -u postgres psql -X -w -At -d postgres \
  -c "SELECT datname FROM pg_database WHERE datname IN ('star_trader_development','star_trader_test') ORDER BY 1;"
HEROKU_SKIP_UPDATE_CHECK=1 heroku apps:info --app star-trader --json
HEROKU_SKIP_UPDATE_CHECK=1 heroku version
HEROKU_SKIP_UPDATE_CHECK=1 heroku help releases:info
HEROKU_SKIP_UPDATE_CHECK=1 heroku help pg:psql
HEROKU_SKIP_UPDATE_CHECK=1 heroku help rollback
HEROKU_SKIP_UPDATE_CHECK=1 heroku help pg:backups:capture
```

Public GETs used Python `urllib.request.urlopen` for `/locations?star={system}` and `/api/locations?system={system}`. The pure replay used `subprocess.run(['bin/codex_exec','ruby','-e',ruby_source], input=json.dumps(rows))`. No remote POSTs were made. The playbook includes a reproducible replay command.

Results and exclusions:

- PostgreSQL socket is accepting connections. Direct local `psql` failed `fe_sendauth: no password supplied`; noninteractive postgres-role probe failed `sudo: a password is required`. No credential search, role change, service change, or DB repair was performed.
- Heroku app info failed `HEROKU_NONINTERACTIVE_LOGIN`. The downstream JSON parser had no response to parse. Consequently no app UUID, domain binding, database attachment/ID, release ID/SHA, dyno state, backup state, pipeline, or staging environment is verified.
- Local `heroku/main` is a cached Git ref, not proof of live release. The host's successful celestial GETs likewise do not prove it belongs to that app.
- No Rails boot, routes task, console, test suite, or asset build was run. `bin/codex_test` installs dependencies and runs `db:prepare`; it is inappropriate in a no-migrations discovery phase. `bin/codex_db_doctor` can source an env file and prints connection details, so narrower explicit probes were used.
- Rails boot warms RabbitMQ connections (`config/initializers/rabbitmq.rb:7-11`). `TICK_BOOTSTRAP=true` can schedule jobs (`tick_bootstrap.rb:1-10`). `Tick.current` calls `first_or_create` (`tick.rb:22-31`). Dashboard and websocket subscription can therefore initialize state. Read-only discovery did not use them.
- No live travel/sentinel aggregate was queried, because DB authentication failed. The lifecycle contract was inspected in code; record-state validation remains a release gate.

## Recommended minimal design and contract decisions

Use **Gm** as the explicit physical unit, matching existing Mkm numerical fields. `1 Gm = 1,000,000 km = 1,000,000,000 m`; 8.2 Gm is 8,200,000 km; 47.6 Gm is 47,600,000 km. Declare fields as radius/apsides, never diameter. Retain full precision for computation; proposed numerical geometry tolerance is absolute `1e-9 Gm` (1 m) plus relative `1e-12` for large magnitudes, subject to solver validation. This is numerical precision within a model, not game accuracy.

Separate physical position calculation from all rendering scale, padding, mesh sizes, camera transforms, and UI rounding. Carry system frame, stable identity, hierarchy, clock, unit, and dataset version in a shared server-owned snapshot. Return full XYZ with `z=0` for the existing planar model. Compose parent/local transforms before Euclidean distance. Unknown positions must be explicit errors; preserve the current zero local offset for cities only as an identified body-center approximation.

A versioned calibration catalog should override importer-owned orbital fields by validated composite identity. Prefer an immutable code-shipped catalog over repeatedly updating legacy `locations` values: imports then cannot overwrite the calibrated numbers, and release rollback restores data and code together. Still validate parent and identity preconditions, and fail on mismatch. If M1 instead selects database-backed orbital records, require a scoped before/after journal and guarded data reversal; code rollback alone is insufficient.

Following Dustin's clarification, retain and correct the **existing evolving orbital calculator**. The original static-reference proposal is superseded as the default. Establish explicit stellar mass in kg, per-body phase/epoch, clock, and distance-target semantics; calibrate orbital bounds separately from mass and rendering. The current masses/phases are not trustworthy game observations. No additional gravity simulation is required. Even a circular approximation needs independent angular placement for Pyro IV/V. Do not manufacture phase by array order, hash, or changing radii.

For travel, preserve departure-time direct separation, existing gateway rules, minimum duration, ceiling, RabbitMQ routing, and saved in-flight trips. Resolve the speed boundary against the clarified practical Stanton scale: legacy duration consumes scene-unit distances, whose Stanton magnitudes already approximate the requested Gm values. The revised proposal keeps numeric ship speeds and defines their calculator rate explicitly in Gm/tick, subject to the caller/catalog audit and before/after duration checks. The earlier blanket `5 * speed` conversion would preserve a source-comment interpretation while changing this practical behavior; it is no longer the default recommendation. Never make speed depend on a future display transform or assume km/s without evidence.

Dustin has confirmed star-distance calibration goals, practical scaling comparable to current Stanton, and inclusion of stellar-mass adjustment. This does not establish numerical masses, periods/phases, the acceptance meaning of an elliptical target, or independently confirm host/hierarchy changes. Apply Levski through the observed Delamar host unless contrary evidence is supplied. The acceptable fidelity to actual game angular positions also remains unresolved. Detailed decision gates are in the playbook.

**Next executable milestone: M1 — authenticated identity/data audit and calculation contract.** The first local actions are read-only inventory and contract work; implementation and production execution remain subsequent assignments. M0 documentary work is complete, while unavailable runtime evidence is explicitly carried forward.
