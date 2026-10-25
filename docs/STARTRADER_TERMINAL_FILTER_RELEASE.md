# StarTrader terminal filter release evidence

24 October 2026 (America/Vancouver). **M1–M7 complete: production v171 verified.** [Live market](https://startrader.altama.energy/market) · [playbook](STARTRADER_TERMINAL_FILTER_PLAYBOOK.md) · [live evidence](STARTRADER_TERMINAL_FILTER_LIVE.json).

## Delivered behavior

A bounded remote Terminal combobox below Star System stages selection until explicit Apply. Applied external terminal identity produces player-facing Buy then Sell groups, full filtered counts, overlap and independent 50-row pages. Missing quotes and optional Commodity associations remain visible; no selected terminal keeps the legacy feed. Scoped invalidation and explicit Refresh preserve drafts, focus and scroll. Paging uses normal Turbo Drive GET navigation, the playbook's history fallback; map/details reinitialize on page visits.

## Actual release and integration

| Item | Verified value |
| --- | --- |
| Application | Heroku star-trader, UUID 6b362b75-1732-42a4-9888-669a393f7f82 |
| Public domain | startrader.altama.energy |
| Database add-on | postgresql-metric-14477; PostgreSQL 16.14 |
| Release | **v171**, succeeded, created 2026-10-25T02:50:55Z |
| Full deployed source | **4d2d7cb97bea19f629a8f71262eaabf10748ebb8** |
| Production integration | [PR #33](https://github.com/Seggellion/startrader/pull/33), then history fix [PR #35](https://github.com/Seggellion/startrader/pull/35) |
| Mainline integration | [PR #34](https://github.com/Seggellion/startrader/pull/34), then [PR #36](https://github.com/Seggellion/startrader/pull/36), merge 8eeee1e147f1a9220c151eb93323b8c45bcaa8b5 |
| Fresh backup | **b004**, Completed at 2026-10-25T02:49:10Z; previous b003 retained |
| Compatible prefeature source | v168 / v170 rollback slug, 9bc1d17614e667b1226671e413d4e5591d9b3380 |
| Processes | web.1 and worker.1 up on v171 at all observation samples |

The qualified production merge tree exactly matched f544f35da09086694d17659dd1c7a67b22199c23 and re-passed focused qualification after integration. The mainline merge tree matched its tested head 523e8318e008a35b36a42939e298b3f77e0766bb. Both fix PRs passed GitGuardian. User approval explicitly permitted publishing the operational details in these documents.

Production starts from the deployed v168 source. Mainline already contained separate regression repairs and cargo-price widening; those application/schema changes were excluded from production. The final documentation closeout commits are separate from the immutable running source above and do not require another runtime deployment.

## Index and asset verification

The standalone pg-only process applied exactly 20261025010000 and 20261025010100 during v169. Both survived rollback and were audited read-only on v171:

- index_terminals_on_unique_api_id: unique btree(api_id), predicate api_id IS NOT NULL, ready and valid.
- index_production_facilities_on_id_terminal: nonunique btree(id_terminal), ready and valid.

No unrestricted db:migrate, deduplication or catalog repair ran. The unrelated cargo migration 20261024170000 remains absent in production, with both cargo price columns still numeric precision 10. The explicit database-name gate and duplicate audit were verified. Local rehearsal covered concurrent down/up, duplicate refusal, wrong database refusal, exact two-version application and idempotent verification.

Heroku ran rake assets:precompile successfully in 5.19 seconds. Three served digested feature controller modules were fetched and compared to the deployed source; four application stylesheet responses returned nonempty HTTP 200. The [live evidence](STARTRADER_TERMINAL_FILTER_LIVE.json) records asset URLs and SHA-256 values. No digested file was hand edited.

## Executed local qualification

Dedicated loopback test/preview/scale databases were created under a non-superuser local role before db:prepare or synthetic seeding. Credentials remain ignored. Preview fixtures contained 830 terminals and 2,590 offers; production data was not imported.

| Check | Actual result |
| --- | --- |
| Final focused production integration | **44 tests / 304 assertions**, no failures/errors/skips |
| Mainline full suite with history fix | **499 / 5716**, no failures/errors/skips |
| Broader production-line qualification before the two-link history fix | 482 / 5394; 33 failures and 25 errors |
| Fresh v168 comparison | 468 / 5247; 34 failures and 26 errors |
| Failure identity comparison | **Zero new failing identities**, 58 retained baseline cases |
| Official Chrome isolated acceptance | **26 checks**, zero page/console errors |
| Terminating isolated asset build | Passed |

The production-line broader suite is **not green**. The two removed baseline cases were relevant importer fixture defects; unrelated repairs were not deployed to conceal failures. See [exact regression comparison](STARTRADER_TERMINAL_FILTER_REGRESSIONS.json). The history fix changed only two paging link targets at runtime; final focused and Chrome tests cover the added regression.

Official executable: C:\Program Files\Google\Chrome\Application\chrome.exe, version **155.0.8059.41**, valid Google LLC Authenticode signature. Bundled Playwright drove that explicit binary. No other browser was launched.

[Chrome acceptance](STARTRADER_TERMINAL_FILTER_CHROME.json) covers keyboard/IME, delayed response/JSON races, clear/system/selection races, error/retry, staged Apply/reset, long labels at 320 px, actual direct/Back/Forward row state, independent pages, overlap/missing quotes, stream injection prevention, one-active/one-pending throttle, explicit bulk Refresh, stale navigation rejection, draft/focus/scroll and legacy/map/details. Separate [touch evidence](STARTRADER_TERMINAL_FILTER_TOUCH.json) is Chrome emulation, not a physical-device claim. Roles/labels/state/announcements were checked; no physical screen-reader session is claimed.

## Performance and limits

[Standalone HTTP benchmark](STARTRADER_TERMINAL_FILTER_HTTP.json): 30 warm requests per endpoint on the recorded preview. Lookup server p95 **17.130 ms**, grouped **174.710 ms**; wall p95 **33.295 / 178.654 ms**. Maximum bodies **3700 / 174436 bytes**. Lookup <=20 options/20 KiB, rendered offers <=100.

[Separate Chrome timings](STARTRADER_TERMINAL_FILTER_BROWSER_TIMING.json): 30 warm full navigations; p95 TTFB **341.6 ms**, download **1.7 ms**, response-end to DOMContentLoaded **486.2 ms**, controls/two animation frames **879.0 ms**. Server p95 during this rapid map/browser workload was **302.355 ms**, slightly above the standalone target. Earlier competing-load HTTP measured 333.798 ms. Idle HTTP budgets passed; no SLA under all workloads is claimed.

[Scale evidence](STARTRADER_TERMINAL_FILTER_SCALE.json): 830/2590, 8300/25900 and 83000/259000 terminals/offers. Bounds held at <=20 options, <=20 KiB, <=100 rows and **8 data statements**, including association access on both overlapping in-memory row copies; BEGIN/SET/COMMIT are separate. At 100x the final broad lookup median was **277.13 ms**, max **311.65 ms**; an earlier run reached about 750 ms. Revisit normalized/trigram search when growth/observed p95 warrants it. No extension was added.

## Safe live verification

Sixteen SQL/HTTP checks passed against v171, comparing representative full scopes and rendered rows at the recorded snapshot:

| External terminal | Buy | Sell |
| --- | ---: | ---: |
| 27, Admin - GrimHEX | 14 | 89 |
| 29, HDMS-Bezdek | 5 | 9 |
| 52, known nonmarket Levski | 0 | 0 |
| 262, Platinum Bay - Port Tressler | 1 | 1 |
| 778, market Levski | 16 | 77 |

Independent Sell page 2 on terminal 27 contained 39 rows. Strict invalid IDs and incompatible systems failed closed. Lookup JSON was bounded, malformed shape returned 400 and overlength query 422. Sadaryx survived the missing Commodity association. Missing-quote memberships and decimal player Buy/Sell prices were checked directly against read-only SQL. Legacy mode stayed ungrouped.

Live official Chrome passed **8 selector/layout checks**, **6 state checks** and **2 touch widths (320/375)**. The exact direct page 1 -> page 2 -> Back -> Forward -> reload regression passed with 50/39 actual Sell rows. Both produced equal row IDs on each side, unique DOM identities, Refresh kept drafts, known nonmarket context remained, invalid selection cleared safely, and staged incompatible system changes restored the legacy Pyro map on Apply. Desktop and mobile selected controls were visually inspected.

Map readiness confirmed a valid canvas and orbital-v3:cfc59e789927b6af at tick 703684. The earlier loading screenshot was not used as readiness proof. Protected trade, public API, import, travel, tick and orbital source is unchanged from v168. No production imports, seeds, test trades, new journeys, fabricated streams or artificial ticks were issued.

## Observation and rollback readiness

Fresh Chrome observation: **2026-10-25T02:52:15.331Z to 2026-10-25T03:02:15.340Z**, **600.009 seconds**. Zero page/console errors. Natural market-row messages: **0** (applicable: 0). If zero, this is a live stream coverage gap; deterministic isolated stream/race proof supplies that coverage.

Platform/HTTP samples: **2026-10-25T02:51:43Z through 2026-10-25T03:02:25Z**, elapsed **642 seconds**, 6 bounded samples. All three safe endpoints returned 200; every sample retained exact v171 and healthy web/worker. No sampled 5xx responses or crashes. Some bounded samples included H27 client-interrupted requests during navigation qualification; causation is not established, per-sample tallies are retained and not summed as unique events. Logs are bounded, not continuous coverage.

Sampled server time ranges: lookup **13.051–81.637 ms**, grouped terminal 29 **63.069–160.707 ms**. These few live samples are not p95 benchmarks. Tick advanced naturally **703677 -> 703719**, the worker heartbeat stayed active, and the aggregate of six unfinished journeys matched the predeployment snapshot throughout. No tick schedule/config was changed.

Rollback remains the compatible prefeature v170/v168 slug, full source 9bc1d17614e667b1226671e413d4e5591d9b3380, with the additive indexes retained. Recheck current release ownership before rollback; use the established Heroku rollback path, verify both processes/source, then recheck market/map. Do not restore the database, remove compatible indexes, reimport, reset ticks or recompute journeys for a UI rollback. This project made no config-var changes.

## v169 incident and corrected release

v169 deployed production merge 6636ff5af84ccc289c0bfc55f78a12bda312418e after backup b003. The first ten-minute infrastructure/Chrome observation was healthy, but an additional first-pagination Back case exposed URL/row divergence: page-1 URL restored while 39 page-two Sell rows remained. That functional failure triggered rollback to v168 as **v170**, preserving both additive indexes and business data.

The missed first-navigation case was added explicitly. The permitted full-GET fallback now passes isolated and live tests on v171, followed by the fresh observation above. See [incident evidence](STARTRADER_TERMINAL_FILTER_HISTORY.md). The failed v169 window is not substituted for replacement qualification.

Deferred data issues: orphan nonmarket terminals, stale upstream catalog data, unmatched Commodity records and unrelated commodity/cargo repairs remain separate work. Search eligibility and missing-quote policies intentionally avoid age cutoffs or data repair.
