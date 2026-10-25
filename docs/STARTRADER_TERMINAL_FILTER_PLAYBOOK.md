# StarTrader terminal filter project playbook

Date: 24 October 2026
Owner: Dustin Hill
Executor: Codex in the StarTrader repository
Discovery source: `STARTRADER_TERMINAL_FILTER_DISCOVERY.md`, inspected at `59ff510fab6d09a14e10518bac5f931ccde98f44`
Document status: M1–M4 implemented and qualified locally. M5 integration is in progress; production has not yet been deployed.

## 1 Outcome and scope

Add a searchable Terminal filter below Star System in the commodity Market Filters panel. Selecting a terminal must remain usable with a growing catalog and ambiguous names. Applying that selection must show **Buy** followed by **Sell**, with player-facing explanations, complete filtered offer counts, and independent pagination.

Carry the project through implementation, meaningful Google Chrome qualification, integration, production deployment, and live verification. The kickoff prompt starts execution at M1; completed discovery is M0. Keep the playbook in `docs/STARTRADER_TERMINAL_FILTER_PLAYBOOK.md` and record decisions and milestone evidence there or in linked documents under `docs/`.

The work is limited to terminal selection, market query/rendering/state, required additive indexes, and correct refresh behavior. Preserve existing trade execution, public commodity API semantics, import identity behavior, map/details integration, orbital-v3 anchored progression, spaceship travel timing, tick cadence, and existing journeys. No catalog reimport, production seeding, broad data repair, new frontend framework, or unrelated migration is required by default.

## 2 Discovery findings that determine the design

The supplied discovery provides source and read-only database evidence, not implemented feature behavior. Revalidate mutable baselines in M1 rather than repeating broad discovery.

| Finding | Design consequence |
| --- | --- |
| 830 terminals, 135 with qualifying commodity data; up to 28 at one host | Search eligible terminals remotely; do not populate a full-catalog select. |
| 21 duplicate normalized-name groups, duplicate codes, labels up to 96 characters | Use contextual wrapping labels and external identity; never use names or code as a unique key. |
| Facilities reference `terminals.api_id`; terminal external 1 had local PK 1354 | Submit `terminal_api_id` and filter `production_facilities.id_terminal`; joining to the terminal Rails PK is wrong. |
| 720 Buy and 1,952 Sell memberships, with 82 overlapping | One offer can legitimately render in both groups. Counts represent memberships, not unique commodities or executable transactions. |
| 14 Buy and 68 Sell memberships lack positive quotes | Preserve existing support predicates and display unavailable prices explicitly. Do not silently make groups positive-price-only. |
| Largest market terminal had 101 rows, with 14 Buy and 89 Sell memberships | Count and paginate each full scope; splitting a previously loaded 50-row page loses data. |
| API buy/sell labels use terminal perspective, unlike market helpers | Reuse player-facing predicates and decimal price methods; do not borrow API direction labels. |
| Existing inputs autosubmit despite an Apply button; filter partial is rendered twice | Implement deliberate draft/applied state and unique responsive control identities. |
| Global stream replaces one ungrouped row, while grouped offers can appear twice | Intercept applicable market row updates in terminal mode and invalidate/requery the grouped snapshot. |
| Bulk ticks/imports suppress row broadcasts | Provide explicit Refresh and honest as-of information; do not promise tick-by-tick freshness. |
| Source data is old while gameplay updates `updated_at` | Do not hide the whole catalog with an age cutoff or label simulation timestamps as upstream freshness. |
| No terminal external-ID index or facility terminal index | Add audited, safe indexes; substring search does not currently justify a trigram extension. |

Important qualification: the recorded 3 ms lookup SQL and 0.73 ms terminal-side SQL were bounded warm-cache plans, not full HTTP/rendering benchmarks. Preview/test profiles were empty of terminals and market rows. Qualification requires populated isolated fixtures and actual Chrome checks.

## 3 Adopted implementation policy

This playbook adopts the discovery's primary recommendations as working product decisions. Record them in M1 and proceed; do not create a redundant approval gate. Revisit only when current evidence reveals a concrete conflict that materially changes behavior.

| Policy | Implementation contract |
| --- | --- |
| Terminal eligibility | Unique positive external ID, resolved host, and EXISTS a valid current-feed row supporting either player action. No new age, visible, live, or commodity-flag cutoff. |
| Selection versus eligibility | Resolve an applied terminal independently of current search eligibility. A known terminal that loses its last offer retains its label and shows empty groups. |
| Buy/Sell | Buy means player buys from terminal; Sell means player sells to terminal. Preserve current `player_can_buy`/`player_can_sell` support predicates. |
| Missing quote | Keep qualified memberships; show No current quote. Show Out of stock or No receiving capacity only from the appropriate verified fields. These states do not replace execution validation. |
| Player Action | Restrict the common offer relation first, preserving existing Any/Buy/Sell/Both semantics; then derive both groups. Always keep both headings. |
| Apply | All changes are drafts until explicit Apply. Terminal search, selecting an option, and changing another field must not silently apply results. Remove existing implicit autosubmit behavior for this form. |
| No terminal | Retain the legacy ungrouped feed, its existing action semantics, and 50-row paging. |
| Navigation | Normal GET with Turbo Drive for Apply/Reset; results-frame paging with explicit history promotion and canonical-control restoration. Prove it in M4. |
| Refresh | Applicable row-stream messages invalidate terminal results; coalesce requery using applied filters. Include explicit Refresh. No new tick polling or importer broadcast system. |
| Layout | One responsive form if the current layout permits; otherwise uniquely identified desktop/mobile forms sharing draft state and restored canonical applied state. |

Existing action semantics have a subtle effect: with Player Action Buy, the Sell group contains the both-qualified subset of the Buy-filtered offers. With Both, the same intersecting offers may appear under both headings, even when one side has no quote. Explain near that filter: “Restricts matching offers. Each heading shows the actions supported by those offers.” Never label membership as guaranteed tradability or arbitrage.

## 4 Request and state contracts

### Market routes and canonical parameters

Preserve `/` and GET `/market`. Extend the existing permitted filters with `terminal_api_id`, `buy_page`, and `sell_page`; keep legacy `page` for ungrouped mode. Sort/direction and all enum inputs remain whitelisted. Use applied canonical parameters for navigation, never current unsaved input values.

Strictly parse a supplied terminal identity as a positive integer within its database column range. Reject arrays, `29junk`, zero, negatives, overflow, and ambiguous duplicate identities. Blank means no selected terminal. Do not use permissive `to_i` or a name fallback.

For a malformed, unknown, deleted, unresolved-host, or duplicate identity, render a visible invalid/unavailable-selection state and empty grouped results with a clear-selection action. Retain an explicit invalid-selection state; never drop the constraint and display the unrestricted feed. A valid terminal with no offers still displays its canonical context and two empty groups.

System, market `q`, commodity, location type, and existing action constraints are ANDed with the terminal. A crafted system/terminal mismatch must show a warning and empty groups; never silently broaden. On interactive incompatible system changes, clear only the draft terminal and announce why. Applied results stay unchanged until Apply. All systems and compatible system changes retain the selection.

Apply resets all relevant page parameters to 1. Clearing the terminal preserves other draft fields and returns to legacy mode only when applied. Reset navigates to `/` without filters. Group paging preserves the other group's page and all applied filters. Normalize malformed pages to 1 and clamp oversized pages to the last nonempty page, or 1 for an empty group.

### Read-only terminal search endpoint

Add GET `/market/terminals`, using existing application access controls. It must not initialize ticks, mutate records, execute trades, process arrivals, or send external messages. Assess inherited menu/settings overhead separately from query-service work.

| Input/output | Contract |
| --- | --- |
| `q` | Selector search only; distinct from market `q`. Require two characters; maximum 100 characters and five tokens. |
| `star_system` | Optional contextual constraint; no restriction permits global search. Invalid supplied constraints must not broaden search. |
| Short query | 200 with empty results, `has_more: false`, and an instructional state. No catalog preload. |
| Invalid input | Structured 400 for malformed parameter shapes; 422 for excessive query/token length. Do not silently remove restrictive tokens. |
| Search matching | AND tokens across OR fields: name, nickname, code, host name, system, planet, moon, parent. Escape wildcard characters and bind all values. |
| Ranking | Case-insensitive exact name/code, then prefixes, then substrings; deterministic name and external-ID ties. |
| Bound | Fetch at most 21 matches; return at most 20 plus `has_more`. Client limit values cannot increase the cap. |
| Fields | `terminal_api_id`, `name`, `code`, `nickname`, `location_name`, `star_system_name`, `context`. No full-model serialization. |

Example response shape:

```json
{
  "results": [
    {
      "terminal_api_id": 29,
      "name": "HDMS-Bezdek",
      "code": "example",
      "nickname": "example",
      "location_name": "example host",
      "star_system_name": "Stanton",
      "context": "example host / Stanton"
    }
  ],
  "has_more": false
}
```

Only the response structure is normative; example descriptive values are illustrative. Do not seed them as production data. Search uses EXISTS to avoid offer-join fanout. Draft commodity/search/action filters must not remove terminal choices. A selected canonical label is rendered from its identity even when absent from current suggestions. Provide an explicit Search all systems action that stages All systems before a global search.

### Accessible selector behavior

Place a full-width labelled combobox beneath Star System. Show name first and wrapping host/system context second; include code and append external identity if context/code still collide. Preserve complete accessible disambiguation and a recognizable selected summary.

Use 250–300 ms debounce, AbortController, and sequence checks before and after JSON parsing. Invalidate requests on query/system changes, clear, selection, disconnect, and navigation. Handle IME composition. Editing a selected label clears its hidden draft ID immediately; an old identity must never submit under edited text.

Support Up/Down, Enter to select without submitting, Escape, Tab onward, active descendant, expanded/controls/autocomplete states, unique option IDs, and polite loading/result/error announcements. Keep focus in the input. Clear removes only the draft terminal and returns focus. Touch options must be usable in a bounded scrolling list at 320/375 px widths. Error/retry must preserve the selected identity and distinguish stale suggestions from current ones. A fallback may use a small server-rendered search page; never generate an 830-option select.

## 5 Query, rendering, and refresh architecture

Extract an application query boundary rather than copying controller SQL into the lookup and grouped rendering. Proposed paths follow discovery and may adapt to repository conventions:

- `app/queries/market_query.rb`: canonical common scope, existing filters, sort whitelist, selected identity, grouped/legacy page results.
- `app/queries/terminal_search_query.rb`: selection eligibility, contextual search/ranking, bounds.
- `app/controllers/market_terminals_controller.rb`: read-only endpoint and deliberate serializer.
- `app/controllers/star_trader_controller.rb`: orchestrate canonical filters/results without duplicating predicates.

The verified join is `production_facilities.id_terminal = terminals.api_id`. An association, if useful, must declare these keys explicitly. Do not use broken `Location#terminals` unless corrected and tested for its actual name-key schema. Preserve existing optional commodity/location joins; four observed Sadaryx offers lacked a Commodity joined by name and must not vanish through an accidental inner join.

Build one fully filtered base relation, including existing action restriction. Derive Buy and Sell scopes using existing model scopes. Count each full scope, then stable-sort and page each independently. Use 50 rows per group; at most 100 offer rows render. Resolve terminal once and eager-load shared associations. Distinct offers remain separate; do not deduplicate commodity names or merge prices.

Preserve current sorting options, default updated DESC, NULLS LAST, and a deterministic identity tie-breaker. Align SQL price sorting with Ruby's positive-local fallback: negative local values must not sort as the displayed price when display uses a positive imported fallback. Missing or unsupported side quotes sort as missing. Fix this narrowly without rewriting transaction prices.

Keep one outer `market_results` frame. Add canonical terminal summary, generated/as-of timing, clear/Refresh actions, then Buy and Sell sections. Each has full matching-offer count, showing range, empty state, and independently labelled controls. Do not sum overlapping memberships and call the result unique offers. Group-specific DOM IDs must be unique when one offer appears twice; retain legacy row IDs without a terminal. Facility PKs churn on import, so no persisted browser state may assume they survive replacement.

Market query results should return canonical applied parameters, terminal/selection status, and both page metadata objects. Serialize applied state safely into the frame for refresh/history synchronization. If concurrent transactional imports cause inconsistent counts/lists, load the query snapshot within a narrowly scoped consistent read transaction and force needed relations inside it; do not wrap dashboard initialization writes in a read-only transaction.

In terminal mode, intercept only the known market-row replacement stream action before its ungrouped renderer runs. Suppress that replacement, mark results dirty, and refresh using the applied canonical URL. Preserve unrelated Turbo streams and legacy mode. Prototype against installed Turbo rather than assuming a hook works. Coalesce bursts to at most one refresh per second, with one active request and at most one pending invalidation. Reject stale responses after filter/navigation changes. Preserve scroll/focus; defer disruptive refresh while keyboard interaction is active and show Updates available. Do not destroy unsaved drafts on an automatic refresh.

Explicit result navigation discards drafts and restores applied controls; automatic refresh preserves drafts. This distinction must be tested. Source/simulation timestamps must remain distinguishable. Explicit Refresh must see bulk-import/tick changes even without row broadcasts; no promise of continuous freshness is made.

For Apply/Reset use Turbo Drive full GET so controls, address bar, and results agree. For results-frame paging use explicit history promotion and canonical state restoration for both responsive forms. Test back/forward and refresh. If the installed Turbo behavior cannot satisfy this reliably, use normal GET pagination as a documented simplification rather than shipping inconsistent history; keep independent group parameters and assess the map reinitialization tradeoff.

## 6 Milestones and execution discipline

M0 is the supplied discovery. M1–M7 below are pending. Execute sequentially, keeping affected checks proportional to each change. No multi-agent delegation is required; do not spawn agents unless separately authorized by the user or applicable instructions.

For each milestone record status, exact commit, files changed, actual commands, pass/fail evidence, limitations, rollback/recovery, and next step. Planned commands are not executed evidence. Do not run production imports or test trades. Preserve secrets and unrelated work.

### M1 Revalidate baseline and implement identity/query foundations

**Prerequisite:** Read discovery/playbook and repository instructions. **Primary files:** routes/controller baseline, Terminal/ProductionFacility as needed, new market query, fixtures/query tests, additive index migrations.

1. Revalidate `/home/dusti/startrader`, HEAD/branch/worktrees/remotes and dirty state using Linux Git. Discovery inspected branch `codex/full-regression-repair`; it is not automatically the correct feature base. Preserve `.claude/`, existing worktrees and Zone.Identifier artifacts.
2. Confirm fresh app/domain/database/release/schema metadata. Discovery observed Heroku `star-trader`, add-on `postgresql-metric-14477`, successful v168 short source `9bc1d176`; recorded full SHA was `9bc1d17614e667b1226671e413d4e5591d9b3380`, not freshly retrieved slug evidence. Reconcile current source drift before selecting a feature base.
3. Inspect pending migrations, especially `20261024170000_widen_cargo_unit_prices.rb`, which was beyond the recorded production release. Base the feature on the accepted integration baseline or port only its changes through the established policy. Do not silently release regression-repair commits or run unrelated pending migrations.
4. Record the adopted policy table, exact request/JSON/state contracts, and existing stream identifiers. Confirm ordinary orbital/travel behavior remains outside feature scope.
5. Inspect `bin/codex_exec`, `bin/codex_test`, initializers, and environment profiles. Establish dedicated populated test/preview databases and prove they are not production or shared development before `db:prepare` or test runs. Existing profiles had no market data. Use synthetic factories/fixtures, not production imports.
6. Implement strict terminal identity, the common query boundary, full-scope grouping, stable price sorting, optional-association handling and independent page metadata. Preserve legacy behavior through tests.
7. Fresh-audit duplicate external terminal IDs and add a unique index on non-null `terminals.api_id` and an index on `production_facilities.id_terminal`. Use separate additive migrations and online/concurrent creation with `disable_ddl_transaction!` where appropriate. Recheck duplicate/race handling under terminal imports; do not add a unique terminal/commodity offer composite.

**Suggested initial read-only commands:**

```bash
cd /home/dusti/startrader
git status --short
git rev-parse HEAD
git worktree list
git remote get-url origin
git remote get-url heroku
bin/codex_exec --ruby-diagnostics
HEROKU_SKIP_UPDATE_CHECK=1 heroku apps:info --app star-trader --json
HEROKU_SKIP_UPDATE_CHECK=1 heroku releases --app star-trader
HEROKU_SKIP_UPDATE_CHECK=1 heroku domains --app star-trader
```

Inspect wrappers before use; source line references in discovery belong to its commit. Use read-only bounded database audits without exposing credentials. Rails boot can connect RabbitMQ, tick recovery can enqueue, and `Tick.instance` can create data; a console is not automatically read-only.

**Verification:** Internal PK differs from external ID; same name/code across hosts/systems; invalid/duplicate identity; missing host; no sibling leakage; scope/action/price parity; no accidental loss of missing Commodity rows; >50 memberships on each side; overlap/empty/count/page behavior; index/import regression tests.

**Exit:** Query and identity contracts pass on populated isolated data; migrations are additive, separated from unrelated work, and tested for the actual PostgreSQL migration path.

**Recovery:** Revert feature code locally. Inspect failed concurrent indexes for validity/name before a deliberate cleanup/retry. Never deduplicate production records or blindly retry a failed unique index.

### M2 Build bounded terminal search and selector

**Prerequisite:** M1 identity/eligibility and query contracts. **Files:** lookup query/controller/route, `_terminal_selector.html.erb`, `terminal_selector_controller.js`, controller registration, filter partial.

Implement the endpoint and combobox contracts in section 4. Reuse the orbital controller's abort/sequence pattern without changing orbital logic. Build contextual labels and small responses. Handle global/system search, strict IDs, loading/error/empty/has-more states, IME, clear/selection, and duplicate responsive IDs. Avoid parent autosubmit and bound all result queries.

Use Chrome with controlled delayed fetch and JSON parsing to prove stale results cannot overwrite new query/system/clear/selection state. Verify duplicate-name options select the right external ID. Test official Google Chrome, keyboard operation and narrow mobile widths; an installed Chromium binary is not a permitted substitute.

**Exit:** At most 20 options, payload at most 20 KiB, no catalog preload, safe search parameters, accessible and deterministic selection. Search and selecting do not change applied results.

**Recovery:** Remove the new route/selector coherently while retaining compatible additive indexes. No data repair is required.

### M3 Render terminal Buy and Sell groups

**Prerequisite:** M1 query output and M2 selected identity. **Files:** `_market_results.html.erb`, new `_market_group.html.erb`, `_market_row.html.erb`, helper, controller integration.

Implement the summary and ordered groups from section 5. Show player-facing price meaning, unsupported quote and actual stock/capacity states without implying executable availability. Retain decimal precision. Maintain map/detail selection and optional association fallbacks. Render both headings for all terminal-applied states, including empty and invalid selections.

Add separate `buy_page`/`sell_page` controls, full counts, clamping, deterministic ties, and applied-filter link preservation. Do not fetch one common page and partition it in Ruby. Preserve legacy ungrouped row IDs, pagination and action semantics without a terminal.

**Verification:** Buy-only, Sell-only, valid both-price synthetic offer, status/stock-only missing quote, zero stock/full receiving capacity, negative-local fallback sorting, absent Commodity, independent >50-row groups, overlapping DOM copies, import-related PK/page churn. Actual discovery examples are semantic references; synthetic IDs must not depend on production records.

**Exit:** Complete correct filtered scopes, prices and counts are visible in Buy then Sell; no N+1 or sibling-terminal leakage; legacy feed remains covered.

**Recovery:** Revert grouped templates/controller integration as one compatible unit; do not alter upstream price data.

### M4 Make filter state navigation and streams coherent

**Prerequisite:** M2/M3 integrated. **Files:** `market_filters_controller.js`, new/narrow `market_results_controller.js`, index/filters/results markup, stream adapter and system tests.

1. Replace implicit input/change submit with staged Apply for all panel fields. Synchronize responsive draft copies or render one shared form. Reset, clear, incompatible-system changes, selected labels and hidden IDs must agree.
2. Implement canonical GET URLs, Apply page resets, frame history promotion, and restored controls/pages on refresh and back/forward. Direct links cannot depend on localStorage or previous autocomplete responses.
3. Prototype and implement the terminal-mode stream invalidation adapter. Prove original ungrouped replacements never enter grouped results, while legacy and unrelated streams retain their behavior. Requery membership, counts, sort and pages together.
4. Coalesce stream bursts, retain applied parameters, preserve drafts on automatic refresh, reject stale frame responses, and protect focus/scroll. Include Updates available and explicit Refresh for suppressed bulk updates.
5. Verify map/details behavior through Apply navigation and responsive tabs. User-initiated paging restores canonical controls; automatic refresh retains uncommitted drafts.

**Verification:** Chrome slow-response races, IME, Enter/Escape/Tab, two form copies, changed hidden identity, incompatible crafted URLs, share/refresh/back/forward, Apply/reset/clear, stream membership changes on both sides, count changes, last-page disappearance, one-active/one-pending refresh, disconnect cleanup, and no surprise application of drafts.

**Exit:** State, results, URL/history and stream behavior agree. If frame history is unreliable, the documented full-GET paging fallback passes the same state tests before completion.

**Recovery:** Revert state/stream changes coherently with grouped mode. Do not reset ticks, jobs or market data.

### M5 Qualify an integrated release candidate

**Prerequisite:** M1–M4. **Files:** controller/query/model/import/system tests, migrations, build assets, release evidence.

Populate isolated fixture scenarios for terminal identity collisions, action/quote edge cases, >50 rows per side, missing associations, and mutable/imported datasets. Run focused tests, then the relevant required broader suite. Separate existing failures from feature regressions; historical full-regression reports do not qualify this feature.

Inspect test-wrapper behavior before execution. `bin/codex_test` installs dependencies and runs `db:prepare`. Only run it after database isolation is proven. Start test infrastructure with broker/network isolation according to current repository conventions. Run Chrome system tests with the actual official Chrome executable identified in evidence.

Test-command families to resolve against current tooling and actual added paths:

```bash
bin/codex_exec bundle exec rails test test/controllers/star_trader_controller_test.rb
bin/codex_exec bundle exec rails test test/controllers/market_terminals_controller_test.rb
bin/codex_exec bundle exec rails test test/models/production_facility_test.rb
bin/codex_exec bundle exec rails test test/services/admin/data/terminals_importer_test.rb
bin/codex_exec bundle exec rails test:system
```

New controller/system paths must exist before running their commands; add extracted query and FacilitiesPopulator/API/TradeService regression paths as located. Do not fabricate successful outputs. Use a terminating verified CSS/asset build, not the package's CSS `--watch` script, and build source modules rather than patching `public/assets` digests.

Performance qualification:

- Maximum 20 lookup options, JSON at most 20 KiB, maximum 100 rendered offer rows, and no full catalog in page HTML.
- Group query boundary at most 8 SQL statements including identity, both counts, both row queries and shared preloads; statement count stays constant from 1 to 100 loaded rows. Measure unrelated menu/settings/request overhead separately. Record a justified budget adjustment if the actual association design requires it; do not hide queries.
- Recorded preview machine: at least 30 warm samples, lookup server p95 below 150 ms and grouped feed below 300 ms. Record test conditions, payloads and Chrome network/render costs separately.
- Synthetic isolated 10x and 100x fixtures: inspect worst terminal, duplicate-context, substring, no-match and system-filter query plans, buffers/loops and allocations. Bound payload/DOM independently of catalog growth. Do not seed production or add trigram extensions without measured need.
- Chrome at desktop panel sizes and 320/375 px mobile widths: full labels, touch/scroll, focus, announcements, unique IDs, hidden form state, map/details and accessible paging.

Integrate through normal repository/PR policy. Record the exact final integrated SHA and recheck affected behavior after merges/conflicts. Prepare `docs/STARTRADER_TERMINAL_FILTER_RELEASE.md` with baseline app/domain/database/schema, candidate SHA, tests, browser binary, benchmarks, migration versions/order, asset build, release commands, rollback triggers and deferred data issues.

**Exit:** Exact candidate has meaningful query, UI, stream, regression, build and Chrome evidence; migrations and production source drift are reconciled; no invented success or hidden policy change remains.

**Recovery:** Revise the candidate locally; preserve evidence. No production activation yet.

### M6 Deploy to verified StarTrader production

**Prerequisite:** M5 complete, fresh identity/source/schema preflight, and established repository deployment policy satisfied. Production delivery is part of the project scope when the kickoff is invoked; no repeated routine confirmation is needed. Real missing access, conflicting release ownership, or an applicable explicit approval rule must be stated precisely.

1. Verify current Heroku app UUID/domain/database, actual full slug/source SHA, release/process state, and pending migrations. A cached Git remote or old v168 record is insufficient. Reconcile any intervening deployment before release.
2. Audit duplicate external terminal IDs and index validity again. Record importer concurrency and a bounded failure/recovery procedure. Prepare a recoverable backup according to the established release process; no data backfill/import is planned.
3. Record the immediate prefeature rollback release/source. Preserve any already deployed cargo-price widening, orbital-v3 schedule and travel timing. Old v166/v167 rollback recipes may now be incompatible.
4. Deploy the exact qualified integrated SHA through the established PR/Heroku Git workflow. Verify build/release success and exact slug SHA. Do not force-push or treat a successful push as release completion.
5. Execute only the planned feature index migration process. Discovery found web/worker Procfile entries but no release command: **do not assume Heroku Git runs migrations**. Review all pending versions; choose explicit feature migration versions rather than an unrestricted `db:migrate` that could deploy unrelated cargo changes. Record actual command/version and index validity. Order code/index activation according to tested compatibility; index absence must not corrupt selection correctness.
6. Verify web/worker health, digested assets, route registration, and index/schema state. Restart only what the actual release process requires.
7. Run safe public/read-only market lookups and Google Chrome selection/group/navigation checks. Never import data, execute a trade, create test travel, or advance production ticks for this UI release.

**Conditional deployment example:** only after the release route, remote and SHA are verified:

```bash
git rev-parse --verify "${STARTRADER_TERMINAL_RELEASE_SHA}^{commit}"
git push heroku "${STARTRADER_TERMINAL_RELEASE_SHA}:refs/heads/main"
HEROKU_SKIP_UPDATE_CHECK=1 heroku releases --app star-trader
```

Populate the task-specific SHA variable from the qualified manifest. Resolve exact one-off migration commands during M5; they are not supplied as speculative production instructions here.

**Exit:** Exact feature source, assets and required valid indexes are running on the verified production app. Immediately continue to M7.

**Rollback:** Revert to the immediately preceding compatible feature-free code/assets and leave additive indexes in place. Drop an index only through a separately inspected necessity/recovery plan. Never restore the whole database, reimport facilities, recompute journeys, reset ticks or undo already deployed unrelated schema as routine UI rollback.

### M7 Verify production and close out

**Prerequisite:** M6. Verify actual release/full SHA/schema/assets; bounded selector responses; correct terminal identity; Buy/Sell perspective and counts; independent pages; invalid-selection safety; Apply/reset/history; mobile Chrome; explicit Refresh; and legacy ungrouped mode. Compare representative aggregate counts at a documented snapshot; production gameplay/import activity can legitimately change later values.

Use the same-name Levski/Port Tressler examples only if fresh data still contains them, and a larger terminal for pagination. Do not invent missing live fixtures or create them in production. Stream-race and synthetic both-side-price guarantees remain covered in isolated tests; live inspection verifies the integrated behavior safely.

Observe errors/latency and web/worker health over a recorded bounded period, normally 10–15 minutes of nonblocking observation with work updates; do not sleep through the interval. Watch ordinary stream activity without manufacturing writes. If no message arrives, record the live stream coverage gap and rely on the completed deterministic stream test rather than claiming a live event was observed.

Rollback for incorrect terminal leakage, direction/price reversal, restrictive filters broadening, missing major results, broken Chrome selection/history, stream injection, nonfunctional assets, new feature 5xx, or unacceptable query/load behavior. Verify recovery after rollback.

Finish the release evidence and playbook status with actual release/SHA, schema/index results, test/Chrome/performance/live evidence, and deferred issues. Defer orphan nonmarket terminals, stale upstream data and unrelated commodity repairs explicitly. A deployed-but-unverified build, PR, or local pass alone is not completion.

## 7 Acceptance matrix

| Area | Required proof |
| --- | --- |
| Identity | External ID selects only that terminal, despite PK/name/code collisions; invalid input never broadens. |
| Selector | Bounded remote search, contextual labels, no preload, stale-response safety, valid clear/edit behavior, accessible official Chrome. |
| Direction | Player Buy/Sell matches helpers and execution meaning; API's opposite-perspective labels remain unchanged. |
| Data representation | Missing quotes, stock and receiving capacity remain distinct; decimals/negative-local fallback are correct; optional associations survive. |
| Grouping | Buy then Sell always; full-scope offer counts; overlap permitted; independent 50-row pages and stable clamping. |
| Filters | Existing AND/action semantics; drafts commit only on Apply; no-terminal legacy feed preserved. |
| Navigation | Direct URL, refresh, back/forward, reset and both responsive copies reproduce canonical state. |
| Updates | No ungrouped stream injection; bounded invalidation refresh; preserved drafts/focus/scroll; explicit Refresh sees suppressed bulk changes. |
| Performance | Measured bounded payload/DOM/query count, preview p95 and isolated scale evidence. |
| Release | Exact qualified deployed SHA, feature-only migration plan, valid indexes/assets, Chrome/live checks and compatible rollback. |
| Regressions | No trade/API/import direction change; no orbital, tick, travel-rate or journey mutation. |

## 8 Project status

| Milestone | Status | Evidence to record |
| --- | --- | --- |
| M0 Discovery | Complete | Supplied discovery; recorded source/SQL limits. |
| M1 Foundations | Complete | Revalidated baseline, query/identity tests, safe index plan. |
| M2 Selector | Complete | Endpoint/transport/accessibility and Chrome results. |
| M3 Grouped results | Complete | Complete counts/pages/semantics/legacy coverage. |
| M4 State and updates | Complete | Canonical history and stream correctness. |
| M5 Qualification | Integration in progress | Exact integrated SHA, tests/build/benchmarks/release manifest. |
| M6 Deployment | Pending | Actual release/full SHA and valid feature indexes. |
| M7 Closeout | Pending | Live checks, observation, rollback readiness and final evidence. |

## Execution record — M1 (24 October 2026 Pacific)

- Adopted section 3 policies unchanged; no new product approval gate.
- Verified production app/domain/add-on and actual full slug SHA v168 / 9bc1d17614e667b1226671e413d4e5591d9b3380. Both processes up; no duplicate external terminal IDs; feature indexes absent. Credential-free detail retained in ignored tmp/terminal-preflight.json.
- origin/main is 59ff510 and includes unrelated regression repair. Feature branch codex/terminal-filter and PR release base codex/terminal-filter-production start at deployed v168. Only feature code and relevant test fixture corrections will enter this release; cargo widening stays excluded.
- Created new loopback databases star_trader_terminal_test and star_trader_terminal_preview under a non-superuser local role. Both started empty; separate ignored .env.terminal-* profiles. No reuse of older shared profiles.
- Baseline command: CODEX_ENV_FILE=.env.terminal-test bin/codex_test test/controllers/star_trader_controller_test.rb — 5 tests / 42 assertions, all passed.
- New query command: same wrapper with test/queries/market_query_test.rb — 7 tests / 68 assertions, all passed. Scope includes external-ID isolation, optional Commodity, predicates, full counts/independent pages/clamping, negative-local fallback and <=8 data statements.
- The first 37-test import/model/query run exposed two pre-existing importer fixture defects: missing gateway helper keywords and a fallback fixture that still had a matching API host. Ported only those five fixture-line corrections from accepted origin/main, since meaningful importer qualification is required for the new uniqueness index. No application regression-repair changes are included.
- Isolated db:prepare exercised both concurrent feature index migrations. Separate guarded script/verify_terminal_indexes.rb rehearses duplicate refusal and concurrent down/up; never run it on production.
- M2 files may be present while M1 is qualified; milestone commits stage only the respective files. Full mutable log/results remain in ignored tmp/terminal-m1-*.log.


M1 final verification: 37 tests / 231 assertions, zero failures/errors/skips; concurrent migration rehearsal and duplicate-audit rejection passed. Commands: CODEX_ENV_FILE=.env.terminal-test bin/codex_test test/queries/market_query_test.rb test/controllers/star_trader_controller_test.rb test/models/production_facility_test.rb test/services/admin/data/terminals_importer_test.rb test/services/admin/data/facilities_populator_test.rb; isolated profile + bin/codex_exec bundle exec ruby script/verify_terminal_indexes.rb. Logs: tmp/terminal-m1-final.log and tmp/terminal-m1-indexes.log. Transaction control adds BEGIN/SET/COMMIT outside the <=8 data-query budget.

## Execution record — M2–M5

Implementation commits:
- M1: `a7d1de0`.
- M2: `99b019b5b87056d0aaa0823028afcc99679e6e18`.
- M3: `d1d40dd9875e138d326e3c758c3dd2465d262dd4`.
- M4: `88470962872c5ede687a4ca65f577412a15261a6`.

- M2 implements the strict bounded lookup, contextual accessible selector and one responsive form. M3 implements full-scope Buy/Sell groups, decimal/missing-quote states and independent pagination. M4 implements canonical frame-load restoration and scoped invalidation, with one active/one pending refresh and explicit-refresh intent retained through throttling.
- Actual focused command: `CODEX_ENV_FILE=.env.terminal-test bin/codex_test test/queries/market_query_test.rb test/controllers/market_terminals_controller_test.rb test/controllers/terminal_market_results_test.rb test/controllers/star_trader_controller_test.rb test/models/production_facility_test.rb test/services/admin/data/terminals_importer_test.rb test/services/admin/data/facilities_populator_test.rb` — **44 tests / 302 assertions, zero failures/errors/skips**.
- Actual required broader command: `CODEX_ENV_FILE=.env.terminal-test bin/codex_test` — **482 tests / 5394 assertions, 33 failures / 25 errors**. Fresh v168 archive baseline on the same isolated DB: 468 / 5247, 34 failures / 26 errors. Exact failure-identity comparison has **zero new failures**; only removed cases are the two relevant importer fixture defects. Do not call this suite green. See STARTRADER_TERMINAL_FILTER_REGRESSIONS.json and ignored baseline/candidate logs.
- `script/verify_terminal_indexes.rb` and `script/rehearse_terminal_index_process.rb` ran only in star_trader_terminal_test. They prove concurrent down/up, duplicate refusal, wrong-DB refusal, exact two-version standalone application and idempotent verification. Production process is `script/apply_terminal_indexes.rb`; it loads pg, never Rails, and never runs unrestricted db:migrate.
- Terminating build: isolated `RAILS_ENV=test bin/codex_exec bundle exec rails assets:precompile` passed; existing Browserslist freshness notice remains.
- Official Google Chrome: `C:\Program Files\Google\Chrome\Application\chrome.exe`, **155.0.8059.41**, valid Google LLC Authenticode signature. Bundled Playwright is only the driver; every launch uses that explicit executable. No other browser used.
- Chrome command: bundled Windows node + `test/browser/terminal_market_chrome.cjs`, with TERMINAL_PLAYWRIGHT_MODULE pointing to bundled Playwright and TERMINAL_EVIDENCE_DIR to this chat's visualization folder. Completed 24-check run: zero page/console errors. Strengthened final history/stale-frame and touch checks are recorded in final evidence. Screenshots visually inspected, including a wrapping long terminal selection at 320 px.
- Separate `test/browser/terminal_map_chrome.cjs` readiness check: valid canvas, tick 701104 and retained `orbital-v3:cfc59e789927b6af`. An earlier screenshot taken while loading was not treated as map-readiness proof.
- Real HTTP: `test/browser/terminal_market_http.cjs`, 30 warm samples/endpoint at 830 synthetic terminals / 2590 offers. Server p95 **17.130 ms lookup / 174.710 ms grouped**; max payload **3700 / 174436 bytes**. Lookup <=20 KiB; grouped DOM <=100 offers.
- Earlier competing-load run had grouped p95 333.798 ms; after other Ruby/scale jobs ended, idle runs passed. Independent rapid Chrome navigations measured higher end-to-end costs, retained separately in timing evidence rather than substituted for HTTP server budgets.
- `script/benchmark_terminal_market.rb` ran in a separate guarded scale DB at 830/2590, 8300/25900 and 83000/259000 terminals/offers. <=20 options, <=20 KiB, <=100 rows and **8 data statements** held, including association access on both in-memory copies of overlapping offers. BEGIN/SET/COMMIT control statements reported separately.
- At 100x, broad substring search takes 277 ms median / 312 ms maximum in the final warm samples (an earlier run reached about 750 ms); no claim of a 150 ms 100x lookup. Revisit normalized/trigram search as growth or p95 warrants. Current catalog budgets pass without new extensions.
- Browser findings corrected before qualification: Stimulus context-property collision, late initial restoration, Turbo retaining the outer frame on paging, explicit Refresh losing force intent through throttling, and preloading only one in-memory copy of overlapping rows.
- Integration: normal forward-port PR to origin/main, plus feature-only PR into codex/terminal-filter-production from v168. Only the independently qualified production line is deployed. Unrelated main cargo widening/regression application changes remain excluded.
