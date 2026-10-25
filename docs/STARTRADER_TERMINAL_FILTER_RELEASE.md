# StarTrader terminal filter release evidence

24 October 2026 (America/Vancouver). **v169 rolled back as v170; full-GET history replacement qualified locally and awaiting integration.** M0 discovery is retained at repository root. Implementation contract: [playbook](STARTRADER_TERMINAL_FILTER_PLAYBOOK.md).

## Release boundary

Production was freshly verified as Heroku `star-trader`, custom domain `startrader.altama.energy`, database add-on `postgresql-metric-14477`, successful **v168**, full slug commit **9bc1d17614e667b1226671e413d4e5591d9b3380**, with web and worker up. Exact operational identity is retained in ignored `tmp/terminal-preflight.json`. This is a starting baseline, not a claim that it cannot change before deployment.

The production release line starts at that deployed commit. Origin/main already contains separate regression repair and cargo-price widening; those application/schema changes must not enter this deployment. The feature is also forward-ported through a normal mainline PR so future integration retains it. Production deploys only the separately qualified release-branch merge SHA.

Implementation commits: M1 `a7d1de0`; M2 `99b019b5b87056d0aaa0823028afcc99679e6e18`; M3 `d1d40dd9875e138d326e3c758c3dd2465d262dd4`; M4 `88470962872c5ede687a4ca65f577412a15261a6`. Exact PRs, integrated candidate and actual deployed SHA will be recorded below after integration.

## Qualified behavior

- Strict external terminal identity: facilities.id_terminal = terminals.api_id; malformed/deleted/ambiguous identities never broaden.
- Remote contextual search: <=20 returned options and <=20 KiB, no catalog preload; one responsive staged form, explicit Apply.
- Player-facing Buy then Sell, both headings retained, current predicates/missing quotes preserved; complete counts and independent 50-row pages.
- Canonical URL/history/control state; clearing/system changes; scoped invalidation with one active/one pending refresh, no ungrouped partial injection, preserved drafts/focus/scroll, explicit bulk Refresh.
- Optional Commodity joins retained. Public commodity API, trade execution, import identity code, orbital-v3 schedule, travel timing, tick code/cadence and saved journeys are unchanged by feature source.

## Executed local qualification

Dedicated loopback databases: star_trader_terminal_test, star_trader_terminal_preview and star_trader_terminal_scale, created empty under a non-superuser local role before preparation. Credentials remain in ignored profiles. Preview data is synthetic, including 830 terminals / 2590 offers; no production import was used.

**Focused:** 44 tests / 302 assertions, zero failures/errors/skips via `CODEX_ENV_FILE=.env.terminal-test bin/codex_test` with query, lookup/group controller, legacy controller, model and importer paths recorded in the playbook. The efficiency test reads associations on both in-memory copies of overlapping rows.

**Broader production-line suite:** 482 tests / 5394 assertions, 33 failures and 25 errors. A fresh archive of deployed v168 reproduced 468 / 5247, 34 failures and 26 errors. **Zero new failing identities.** Only the two relevant importer fixture defects were corrected. The production-line suite is **not green**; the 58 retained baseline cases are explicitly listed in [regression comparison](STARTRADER_TERMINAL_FILTER_REGRESSIONS.json). The unrelated application repairs are not silently deployed to make this report green.

**Indexes:** concurrent migration down/up, duplicate refusal, wrong-database refusal, exact standalone two-version application, ready/valid checks and idempotent rerun passed locally. `script/apply_terminal_indexes.rb` loads pg directly, not Rails or tick/broker initializers. It records only versions `20261025010000` and `20261025010100`, refuses duplicate external IDs and incompatible/invalid indexes, and performs no deduplication.

**Assets:** terminating `RAILS_ENV=test bin/codex_exec bundle exec rails assets:precompile` passed on the dedicated profile. Existing Browserslist freshness notice remains. No source digests were hand edited.

## Google Chrome evidence

Official executable `C:\Program Files\Google\Chrome\Application\chrome.exe`, version **155.0.8059.41**, valid Google LLC Authenticode signature. Bundled Playwright drives this explicit binary; no other browser was launched.

[Chrome acceptance](STARTRADER_TERMINAL_FILTER_CHROME.json) contains the completed keyboard/IME, request/JSON/clear/system/selection races, responsive state, Apply/reset/clear, direct/back/forward URLs and actual rows, overlap, full paging, invalid selection, scoped streams, one-active/one-pending throttle, bulk Refresh, disappearing pages, stale frame after Apply, long-label and map/details checks. It has zero page/console errors. Additional touch emulation and final count are appended below.

Screenshots were visually inspected at desktop, 375 px and a wrapping long selected terminal in the 320 px Filters panel. Touch emulation is not a physical-device or cross-browser support claim. Screen-reader support was checked through roles, labels, state and announcements; no physical assistive-device session is claimed.

A separate [map readiness check](STARTRADER_TERMINAL_FILTER_MAP.json) confirms valid canvas, tick 701104 and `orbital-v3:cfc59e789927b6af`. A loading screenshot alone was not accepted as map readiness.

Reproducible browser scripts live in `test/browser/`. Actual commands use the bundled Windows Node/Playwright paths, GOOGLE_CHROME_BIN or its verified official default, and this task's visualization folder for evidence. Driver-module and binary paths are prerequisites, not bundled app frontend dependencies.

## Performance

[HTTP benchmark](STARTRADER_TERMINAL_FILTER_HTTP.json): 30 warm requests per endpoint on the recorded preview. Lookup server p95 **17.130 ms**, grouped server p95 **174.710 ms**; wall p95 **33.295 / 178.654 ms**. Maximum bodies **3700 / 174436 bytes**, respectively. Lookup <=20 KiB and rendered offer DOM <=100.

[Separate Chrome navigation timings](STARTRADER_TERMINAL_FILTER_BROWSER_TIMING.json): 30 warm full navigations at 1500x1000, max 100 offer rows; p95 TTFB **341.6 ms**, download **1.7 ms**, response-end to DOMContentLoaded **486.2 ms**, controls/two animation frames **879.0 ms**. Server p95 during this rapid browser/map workload was **302.355 ms**, slightly above the standalone HTTP target; it is retained rather than hidden by the lower idle result. An earlier CPU-contending HTTP run measured 333.798 ms; standard idle HTTP samples satisfy the specified server budgets. These conditions do not establish an SLA under all loads.

[Scale qualification](STARTRADER_TERMINAL_FILTER_SCALE.json): 830/2590, 8300/25900 and 83000/259000 terminals/offers. <=20 options, <=20 KiB, <=100 loaded rows and **8 data statements** held, including both overlap instances. Snapshot BEGIN/SET/COMMIT controls are separate. At 100x, final warm broad lookup median **277.13 ms**, max **311.65 ms**; an earlier run reached about 750 ms. Do not claim the 150 ms lookup target at 100x. Revisit normalized/trigram search when growth/observed p95 warrants it; no extension was added for today's small catalog.

## Planned production process and rollback

1. Revalidate app/domain/add-on/full slug SHA, process health, pending versions and duplicate external IDs immediately before release. Confirm no intervening ownership/source change.
2. Capture a recoverable Heroku PostgreSQL backup through the established operator path and record its ID/status.
3. Integrate and requalify the exact production-line merge SHA. Deploy that immutable SHA to the verified Heroku remote without force.
4. Run only the audited standalone feature-index process, with the freshly verified expected database name. Never unrestricted db:migrate. Verify ready/valid/unique/predicate/column identity and the two recorded versions.
5. Verify actual release/full slug SHA, assets, processes, read-only aggregate/HTTP results and official Chrome at desktop/320/375 px. No test trades, travel creation, imports, seeding or artificial ticks.
6. Observe bounded health/latency for 10–15 minutes with recorded samples and actual elapsed time. If no natural row message arrives, record the live stream gap and retain deterministic isolated stream proof.

Rollback target is the immediate compatible prefeature release, currently v168, revalidated at deployment. Leave additive indexes in place. Preserve current orbital-v3 anchored progression, travel timing, tick settings, saved journeys and any schema already deployed independently. Do not restore the database, reimport, reset ticks, recalculate journeys or apply a historical orbital-rate rollback to reverse this UI feature.

Rollback triggers: terminal leakage/broadening, direction/price reversal, major missing groups/counts, broken Chrome selection/history, stream injection, nonfunctional assets, new feature 5xx or unacceptable query/load behavior. No rollback has been performed during candidate qualification.

## Production execution and closeout

Pending M6/M7. This section will record exact PR/merge/deployment source, backup, feature index results, live counts/browser results, actual observation window, health and rollback readiness. Candidate qualification is not production completion.

## v169 live history failure and rollback

The qualified production PR #33 merged as 6636ff5af84ccc289c0bfc55f78a12bda312418e; mainline PR #34 merged as 87cc7bae0cff61ef547410905694b45ba7efc3af. Mainline passed 499 tests / 5714 assertions. The production merge tree matched the candidate exactly and re-passed the 44-test focused suite.

v169 deployed that exact SHA. Backup b003 completed. Both feature indexes were applied with the standalone process, valid/ready, and only their two migration versions were recorded; cargo precision remained 10. Sixteen live SQL/HTTP checks and official Chrome selection/touch/map checks passed. The ten-minute observation had no page/console errors or natural market-row messages; bounded server samples had no 5xx/crashes, and the six unfinished-journey aggregate matched predeployment.

An additional first-pagination Back test failed: direct terminal 27 Sell page 1 showed 50 rows; page 2 showed 39; Back restored the page-1 URL but retained page-two data. This was a functional release failure despite healthy infrastructure. The required rollback restored v168 slug/config as v170. The project had made no config-var changes. Both additive indexes and business data remained; rollback source and both healthy processes were verified.

The explicitly permitted fallback is now selected: full Turbo Drive GET paging (_top), retaining independent parameters/counts and all refresh behavior. Each explicit page visit reinitializes map/details. See STARTRADER_TERMINAL_FILTER_HISTORY.md.

Replacement qualification: 44 tests / 304 assertions passed; 26 official Chrome checks with zero page/console errors passed, now including the exact first-pagination regression and legacy Back row restoration. Terminating assets passed. Runtime change is limited to the two paging link targets. Replacement integration/deployment/new observation are pending; the failed v169 attempt is not claimed complete.
