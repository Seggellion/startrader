# StarTrader terminal filter discovery

24 October 2026 (America/Vancouver). Discovery only. Source baseline `59ff510fab6d09a14e10518bac5f931ccde98f44`.

## Recommendation and evidence status

Add a searchable Terminal combobox below Star System. Search on the server, return at most 20 contextual matches, and submit the selected **external terminal identity** as `terminal_api_id`. Keep Apply as the explicit commitment of draft filters. With a terminal applied, render **Buy**, then **Sell**, supported by **Buy from this terminal** and **Sell to this terminal**, with full filtered counts and independent pagination.

Reuse existing player-facing action predicates and decimal price methods. Mark missing quotes and stock/capacity limitations clearly: action support does not prove a trade can execute. Keep the existing ungrouped feed when no terminal is applied. Never select a terminal by display-name matching or equate its host location with a terminal.

This is a proposal, not an implemented feature or an approved implementation contract. Evidence labels:

- **Observed source:** inspected checkout and cited repository paths/symbols/one-based lines.
- **Observed database:** bounded SELECTs against the verified production app's attached database.
- **Requirement:** requested behavior, including Buy before Sell and Google Chrome only.
- **Recommendation:** proposed contract for the implementation playbook.
- **Unresolved:** a decision or validation still needed.

Only this discovery document was created. No application changes, database record changes, imports, preparation tasks, migrations, tests, builds, commits, pushes, or deployments were performed. SQL used read-only transactions. No browser was launched. The attachment contained the request but no screenshot image; the panel was identified from its exact labels and active source, not visual comparison.

## 1. Checkout, instructions, framework, and release baseline

| Item | Observed evidence |
| --- | --- |
| Checkout | `/home/dusti/startrader`, exposed through `\\wsl.localhost\Ubuntu\home\dusti\startrader` |
| Linux Git branch / HEAD | `codex/full-regression-repair` / `59ff510fab6d09a14e10518bac5f931ccde98f44` |
| Initial working tree | Untracked `.claude/` and `STARTRADER_ORBITAL_CALIBRATION_PLAYBOOK.md:Zone.Identifier`; no tracked modifications |
| Existing worktree | `.claude/worktrees/friendly-leakey-963229`, branch `claude/friendly-leakey-963229`, HEAD `fecb49f`; preserved |
| Git usage | Linux Git through WSL only; no checkout, fetch, ref mutation, or worktree changes |
| Instructions | User-supplied AGENTS.md requires Google Chrome only. No additional AGENTS.md found at `/`, `/home`, `/home/dusti` or in the checkout outside dependencies and the separate `.claude` worktree |
| Documentation convention | Root `STARTRADER_*.md` discovery/release/playbook documents; no existing `docs/` directory |
| Verified local runtime | `bin/codex_exec --ruby-diagnostics`: Ruby 3.2.2 and Bundler 2.4.22, without Rails boot |
| Locked dependencies | Rails 8.0.1, pg 1.5.9, Turbo Rails 2.0.11, Stimulus Rails 1.3.4, importmap-rails 2.1.0, Sprockets Rails 3.5.2, Tailwind Rails 3.1.0, Capybara 3.40.0, Selenium 4.27.0 (`Gemfile.lock` dependency entries) |
| Frontend | Import maps/Stimulus/Turbo. `package.json` declares Tailwind `^3.3.0`, PostCSS `^8.4.0`, Autoprefixer `^10.4.0`; CSS watch command only, no JavaScript test command |
| Remotes | `https://github.com/Seggellion/startrader.git` and `https://git.heroku.com/star-trader.git` |
| Fresh production metadata | Authenticated app `star-trader`, Heroku-24, PostgreSQL add-on `postgresql-metric-14477`; web.1 and worker.1 up on current successful release **v168**, description `Deploy 9bc1d176` |
| Production source | `STARTRADER_TRAVEL_TIMING_RELEASE.md:59` records full v168 SHA `9bc1d17614e667b1226671e413d4e5591d9b3380`. Fresh release metadata confirms matching short SHA; full slug commit was not independently retrieved |
| Relevant source drift | Linux Git diff from that full historical v168 SHA to HEAD returned no changes in StarTraderController, Terminal, ProductionFacility, `app/views/star_trader`, TerminalsImporter, or FacilitiesPopulator |

Do not equate checkout HEAD with the deployed release. Later regression repair, including its cargo-price migration, exists beyond v168. Historical test/release reports retain their completed evidence; they do not qualify this proposed terminal feature.

## 2. Current request and rendering flow

### Active implementation

`config/routes.rb:16-17` routes `/` to `StarTraderController#index` and GET `/market` to `#market`. ApplicationController prepends theme paths (`app/controllers/application_controller.rb`, `prepend_theme_paths` and `set_theme_view_path`); no matching theme override of these market templates was found. The active panel is `app/views/star_trader/_filters.html.erb`.

1. `before_action :set_filter_options` runs for index and market (`app/controllers/star_trader_controller.rb:4,111`). It queries distinct location systems/classifications and up to 500 commodities ordered by name.
2. `index` loads dashboard metadata, `Tick.instance`, overview cards and market results (`:6,24`). `market` returns only `_market_results` for a Turbo Frame request; otherwise it renders the full dashboard (`:11`).
3. `market_params` permits `q, star_system, commodity_id, location_type, trade_mode, sort, direction, page` (`:117`). No terminal parameter exists.
4. `filtered_market_scope` starts with `ProductionFacility.left_joins(:commodity, :location)`, requires non-null/nonempty commodity and location names, applies filters, then whitelist-based sorting (`:50-95`). It does not use the API's `trade_available` scope.
5. `load_market` counts the full relation before offset/limit, eager-loads commodity/location and takes 50 rows (`:35-48`). Page is lower-bounded at 1; an excessive page is not upper-clamped.
6. `_market_results.html.erb:9-58` renders one `market_results` frame, full count, loaded size, `_market_row` collection, empty message and Previous/Next. Links carry permitted filters and replace that frame.
7. `_market_row.html.erb:1-69` uses facility.location, player helpers, stock, scu_buy, spread, map-selection data and a facility-specific DOM ID.
8. `StarTraderHelper` delegates to model prices/actions and formats context from system, planet, moon and parent (`app/helpers/star_trader_helper.rb:10-38`).

### Existing behavior and inconsistencies

| Concern | Observed source behavior |
| --- | --- |
| Search | Escaped substring ILIKE across facility/location/commodity and location parent/system/planet/moon. Does not independently search terminal_name/code/nickname (`StarTraderController#filtered_market_scope`) |
| Star System | Exact locations.star_system_name; blank means all. Status bar's default active system Stanton does not apply a Stanton market restriction |
| Commodity | Internal Commodity PK becomes a names subquery; facilities are filtered by commodity_name, not id_commodity |
| Location Type | Exact host classification |
| Player Action | Buy or Sell applies its predicate; Both is their intersection on the **same facility row**, not a union |
| Sort | Updated, location, commodity, player buy/sell prices, inventory, scu_buy labelled Buy-side SCU, and sell-minus-buy spread; default updated DESC, NULLS LAST, facility PK ASC tie-breaker |
| Apply | GET form targets market_results. Despite Apply, input auto-submits after 300 ms and change immediately (`_filters:7`; `market_filters_controller.js:4-25`) |
| Reset | Link to root without the market frame target clears query state by navigation (`_filters:47`) |
| URL/history | Paging links carry params, but no explicit frame history promotion, popstate synchronization or draft/applied state logic exists. Back/refresh restoration of frame-only changes is unverified |
| Responsive layout | Desktop filter width 280 px, xl 320 px; mobile Filters tab. Partial rendered **twice**, including hidden copy (`index.html.erb:20-29`), creating an existing duplicate form-ID risk |
| Live updates | Index subscribes to global market_prices (`index:1`). `ProductionFacility#broadcast_market_row` replaces one `dom_id(facility, :market_row)` with an ungrouped row partial (`production_facility.rb:167-174`). Counts/order/filter membership are not recomputed |
| Ticks | Bulk inventory/price updates suppress row broadcasts (`app/models/tick.rb:37-55,68-87,112-115`). Feed is not proven to refresh every tick |

### Reuse and gaps

Reuse GET routes, sanitization, sort whitelist, player scopes/prices, result frame, row styling, map-selection integration and the Chrome Selenium base.

`search_controller.js` token-filters already rendered DOM items; `sort_controller.js` sorts them. They serve admin lists, not remote autocomplete. No suitable accessible combobox/server autocomplete was found. Do not preload terminals to reuse these controllers.

Reuse the **pattern**, not orbital logic, from `star_system_controller.js:56-74`: AbortController, sequence numbers, checks before/after JSON parsing, cleanup on disconnect (`:42-45`). No new frontend framework is needed.

## 3. Identity, relationships, ingestion and writers

| Entity | Observed relationship |
| --- | --- |
| Terminal | Local PK terminals.id, external api_id, name/nickname/code, typed external hierarchy IDs and location_name. No terminal active/type/availability/source-modified columns (`db/schema.rb:599-619`) |
| Terminal host | `Terminal.belongs_to :location, primary_key: :name, foreign_key: :location_name, optional: true`; save callback normalizes through case-insensitive location-name lookup (`app/models/terminal.rb:5-20`) |
| Location hierarchy | parent_name joins name; system/planet/moon and typed external IDs provide denormalized context (`app/models/location.rb:3-15`; `db/schema.rb:203-261`) |
| Market listing | production_facilities.id is local PK; api_id is external **price-record** ID; id_terminal is external terminal ID; id_commodity is external commodity ID (`db/schema.rb:339-371`) |
| Market host/commodity | Optional associations both join by name (`production_facility.rb:24-30`). No current Terminal association |
| Commodity | Local PK/external api_id; name-key facilities association. Global availability/buyable/sellable flags are not enforced by this feed (`app/models/commodity.rb`; `db/schema.rb:120-148`) |
| Inverse hazard | `Location#terminals` is plain has_many, implying terminals.location_id, which does not exist (`location.rb:30`). Do not build on it without correction/tests |

**Verified terminal-to-feed join:**

```sql
SELECT f.*
FROM terminals t
JOIN production_facilities f ON f.id_terminal = t.api_id
LEFT JOIN locations l ON l.name = f.location_name
LEFT JOIN commodities c ON c.name = f.commodity_name
WHERE t.api_id = :terminal_api_id
  AND f.commodity_name IS NOT NULL AND f.commodity_name <> ''
  AND f.location_name IS NOT NULL AND f.location_name <> '';
```

Name joins above reflect existing host/commodity associations; terminal filtering must use numeric external identity. Production price-record api_id 3831 has id_terminal **1**, terminal api_id **1**, and terminal Rails PK **1354**. Joining id_terminal to terminals.id is incorrect.

### Import/identity survival

- `TerminalsImporter` maps payload id to api_id (`:10-27`). `find_or_initialize_terminal` first matches api_id, then an unambiguous legacy row with **nil** api_id by code/name, else creates a row (`:253-282`). Distinct populated external IDs are not collapsed by equal names/codes.
- Names/context can change on reimport. Location matching prefers typed external ID/classification, then contextual name/code; ambiguity is skipped/reported (`:294-402`). No pruning/deactivation of terminals absent from a payload was found.
- Tests cover repeated import, unique-code legacy adoption, distinct gateway identities and ambiguous fallbacks (`test/services/admin/data/terminals_importer_test.rb:66-205`).
- `FacilitiesPopulator#build_batch_attributes` resolves `Terminal.find_by(api_id: payload["id_terminal"])` and terminal.location, skipping missing terminal/host (`facilities_populator.rb:72-95`). It copies external IDs, raw price/SCU/status fields and names, deriving production/consumption rates from positive buy/sell prices (`:98-132`).
- **Whole market replacement:** `replace_all_from_payload!` deletes all facilities and insert_all's batches transactionally with broadcasts suppressed (`:30-55`). Facility PKs do not survive imports; price-record api_id is unique and duplicate payload IDs are skipped.
- Inventory uses payload inventory, else scu_sell_stock, capped by classification-based max (`:135-144,177-184`). Gameplay/ticks then mutate it independently.
- Commodity import updates external identity or an unambiguous legacy match (`commodities_importer.rb`, `find_or_initialize_commodity` / `find_legacy_commodity`). A rename does not automatically rewrite every name-based facility reference.
- API serialization lives in `Api::CommoditiesController#resource_object` (`app/controllers/api/commodities_controller.rb:29-54`), not a separate serializer directory. It resolves terminals by api_id in bulk. Its location-only terminal_display_name is unsuitable for disambiguating this selector (`production_facility.rb:69-80`).

**Recommendation:** explicitly name the URL parameter `terminal_api_id`; strictly parse a positive integer, resolve exactly one Terminal and filter facilities by that api_id. Add unique terminal api_id indexing after fresh audit. Exclude null legacy identities from selection. Fail visibly on duplicate external IDs instead of choosing first. Never recover an invalid ID by guessing a name/location. External identity stability is verified within the importer contract; future upstream ID reuse is unverified.

## 4. Measured catalog and data quality

Production samples ran **24 October 2026, approximately 17:28–17:31 PDT**. Initial database snapshot timestamp: `2026-10-25T00:28:15Z`. Connections used read-only defaults, repeatable-read READ ONLY transactions, 10-second statement and 1-second lock timeouts, then ROLLBACK. Server: **PostgreSQL 16.14**.

Existing authenticated Heroku credentials were captured into memory without printing/writing them. These are bounded snapshots while production continued operating. Later action/plan samples are separate snapshots, not one transaction with the initial catalog measurements.

| Measure | Observed production result |
| --- | --- |
| Catalog | **830 terminals**, 671 locations, 203 commodities, **2,590 market rows** |
| With market data | **135 terminals**; also 135 with current-feed nonblank fields and at least one action predicate |
| Without market data | 695; catalog includes more than commodity trading |
| Terminal identity | 0 null/nonpositive api_id; 0 duplicate non-null api_id; 0 blank names/location names |
| Duplicate names | **21** lower(trim(name)) groups, **42** involved rows (5.06%); none crosses a host/system in this snapshot |
| Names/codes | All 830 have nickname and code; code is not unique, e.g. PBTRE |
| Hosts | 160 distinct location_name values, including one unresolved value; **108** have multiple terminals. Min/median/p95/max: 1 / 2 / 19.05 / **28** terminals per host |
| Name length | Min 6, median 26, p95 47, maximum **71** characters |
| Context label length | concat_ws(' / ', terminal name, host, system): median **59**, maximum **96** characters before deduplication |
| Terminal host orphans | **5** terminals; none has market rows |
| Market relationships | 0 null id_terminal; 0 external-terminal orphans; 0 location-only rows missing terminal; 0 missing host joins; 0 terminal/market host mismatches |
| Commodity relationship | **4** rows for **Sadaryx**, external commodity 200, lack a Commodity joined by name |
| Duplicate offers | 0 duplicate (id_terminal, id_commodity, commodity_name) groups; no duplicate Commodity names |
| Market rows per terminal | Min 1, median 13, p95 59.6, maximum **101** |
| Terminal age | All 830 updated_at values older than 30 days; range March 2025–July 2026 |
| Source market age | All 2,590 date_modified values older than 30 days; source range March 2025–July 2026 |
| Mutable market updated_at | July–October 2026; this does **not** prove upstream freshness because gameplay changes rows |

| System via terminal host | Terminals | With market | Distinct hosts | Terminals/host min / median / max |
| --- | ---: | ---: | ---: | --- |
| Stanton | 509 | 95 | 103 | 1 / 2 / 22 |
| Pyro | 212 | 31 | 49 | 1 / 2 / 24 |
| Nyx | 104 | 9 | 7 | 9 / 9 / 28 |
| Unknown host | 5 | 0 | 1 | Not joined |

Levski hosts 28 terminals, only one with commodity rows; Ruin Station 24/1; Pyro Gateway (Stanton) 22/2. Largest market terminal Admin - GrimHEX (external 27) has 101 rows, 14 Buy and 89 Sell memberships under current predicates.

| Duplicate displayed name | External api_id | Local PK | Code | Has market |
| --- | ---: | ---: | --- | --- |
| Levski | 52 | 1405 | LEVSK | No |
| Levski | 778 | 2115 | LEVSKI | Yes |
| Platinum Bay - Port Tressler | 140 | 1483 | PBTRE | No |
| Platinum Bay - Port Tressler | 262 | 1599 | PBTRE | Yes |

Terminal has no active/type flag. Host flags are not terminal flags. All-terminal host distribution: 816 availability/live/visible true; five available/live but invisible; four unavailable/invisible; five no host. Of 135 market terminals, 134 have all three flags true and **one is on an invisible host with availability/live true**.

**Recommended eligibility:** resolvable unique positive external ID, host and feed rows supporting either action; currently 135. Do not let draft Commodity/q/Player Action filters remove terminal choices. Do not hide all entries using a 30-day cutoff; all exceed it. Do not import new data for discovery. Keep upstream source age separate from simulated price time. Stricter live/visible policy requires agreement and would remove at least one represented market terminal.

## 5. Verified Buy/Sell semantics

Player perspective is established across ingestion, presentation and execution:

- Import copies raw price_buy/price_sell and derives production_rate/consumption_rate respectively (`FacilitiesPopulator#build_attributes`).
- `player_buy_price` uses positive local_buy_price else price_buy; player_sell_price uses the sell equivalents with decimals (`production_facility.rb:108-114,193-201`).
- Helper/row explicitly label Player buy price and Player sell price (`_market_row:1-4,32-40`).
- `TradeService.buy` charges buy-side price and reduces facility inventory (`trade_service.rb:823-846,932-935`). Sell pays sell-side price and increases inventory (`:1008-1037`). Explicit methods facilities_selling_to_player / facilities_buying_from_player corroborate it (`:1250-1277`).
- API `attributes.sell` uses api_buy_price, and `attributes.buy` uses api_sell_price: those labels use the **terminal perspective** and must not be copied to group headings (`api/commodities_controller.rb:46-47`).

| Group | Parties | Existing qualification | Price |
| --- | --- | --- | --- |
| **Buy — Buy from this terminal** | Player buys; terminal sells | Any positive local_buy_price, price_buy, scu_buy, status_buy or production_rate | Positive local_buy_price preferred, else price_buy; unavailable if no positive quote |
| **Sell — Sell to this terminal** | Player sells; terminal buys | Any positive local_sell_price, price_sell, scu_sell, scu_sell_stock, status_sell or consumption_rate | Positive local_sell_price preferred, else price_sell; unavailable if no positive quote |

These literal OR predicates are `PLAYER_CAN_BUY_SQL` / `PLAYER_CAN_SELL_SQL` and matching Ruby methods (`production_facility.rb:6-22,58-59,91-105`). They describe support/candidates, not executable availability.

**Measured memberships:** 720 Buy, 1,952 Sell, **82 both**, zero neither. **14 Buy** and **68 Sell** memberships have no positive quote. **Zero rows have positive quotes on both sides.** Derived positive-quote counts are 706 Buy and 1,884 Sell. Do not describe the 82 intersections as currently executable two-way trades.

Representative records:

- **HDMS-Bezdek / Laranite**, external terminal 29, price-record 1714: imported buy 7,541.00, local buy 6,024.91, no sell quote, status_buy 7, inventory 5,000. Buy only. Existing synthetic controller regression uses the same direction with a different local price (`test/controllers/star_trader_controller_test.rb:45-70,103-140`).
- **Admin - CRU-L1 / Laranite**: imported sell 8,500.00, local sell 9,863.52, buy zero, status_sell 7, inventory zero. It is a player Sell candidate; zero terminal stock does not prevent receiving the player's goods.
- **Platinum Bay - Port Tressler / Recycled Material Composite**, external 262, record 217: imported buy 10,710.00/local 8,564.63, no sell quote, scu_sell_stock 100. Existing predicates put it in both groups because stock alone satisfies Sell. Its Sell quote must be unavailable.
- **New Babbage / Revenant Tree Pollen**, record 51: status_buy 1 without buy price, local sell 1,651.46. Status alone creates a both-group membership.

Recommended inclusion and representation:

1. Preserve current predicates initially. Include supported sides at zero stock/missing price, with **No current quote**, **Out of stock** or **No receiving capacity**. Counts mean matching offers, not executable trades. Positive-price-only groups would remove 14/68 memberships and currently make Player Action Both empty.
2. Player buying needs simulated inventory; receiving capacity is max_inventory minus inventory (`TradeService#facility_buy_capacity`). Execution candidate scopes are stricter and contain legacy inconsistencies; this browser does not replace transaction validation.
3. Keep source SCU, simulated inventory and receiving capacity distinct. Current scu_buy label is Buy-side SCU; do not rename it guaranteed player selling demand. Imported scu_sell_stock seeds inventory but diverges after gameplay.
4. Raw status codes are tested as >0. No enum mapping precise upstream states was found. This verifies application interpretation, not external live availability.
5. Commodity buyable/sellable and host flags are not existing feed gates. Introducing them is a separate product rule.
6. A commodity can appear once per qualifying group, including a future row with valid quotes both ways. Use different DOM IDs. Two headings do not establish guaranteed profit.
7. Keep distinct offers as separate records; do not deduplicate by commodity name or invent a best-price merge. If duplicates emerge, expose offer api_id/container context. External price IDs are already unique; distinct offers need not be.
8. Scope/sort edge case: SQL price constants use NULLIF(local,0), whereas Ruby falls back unless local is **positive**. Negative locals would sort differently from displayed fallback. None was sampled. Add a focused parity case during query extraction.

## 6. Selector design

**Primary recommendation:** full-width labelled combobox below Star System. At 280/320 px, show name first and a wrapping host/system second line. Keep complete accessible text; selected context remains visible below the input. Include code, and append external ID when name/context/code still collide.

Proposed read-only GET `/market/terminals`:

- Selector `q` is separate from market `q`; optional star_system; maximum input length 100; fixed 20-result cap. Fetch 21 to derive has_more, send only 20. Reject/ignore unbounded client limits.
- Eligibility: unique positive api_id, joined host and EXISTS qualifying feed rows. EXISTS avoids multiplying terminals through market rows.
- Search name, nickname, code, location_name and host system/planet/moon/parent. No separate alias store exists. Bound token count (e.g. five), AND tokens across OR fields, use bound/escaped LIKE parameters.
- Rank exact code/name, prefixes, then substrings with deterministic name/api_id ties.
- Require two characters; blank input instructs “Type a terminal, location, or code”. No default catalog preload.
- Minimal JSON: `{results: [{terminal_api_id, name, code, nickname, location_name, star_system_name, context}], has_more}`. Deliberate serializer, not all model columns.
- Initial market request resolves selected identity independently and renders its canonical label. Search responses cannot erase selection because it falls outside the current result set.
- All systems permits global search. Under a system constraint, an explicit “Search all systems” action stages All systems before searching globally; no required wizard.

Interaction/accessibility:

- 250–300 ms debounce; AbortController plus request sequence checks after response and JSON decode. Invalidate on system change, clear, disconnect/navigation; handle IME composition before sending search.
- Labelled combobox/listbox with expanded/controls/autocomplete, active descendant, unique option IDs and selected state. Up/Down, Enter select, Escape close, Tab onward; selecting with Enter must not submit filters.
- Keep focus in the input. Polite announcements for loading/count/empty/error/selection/clear. Retry preserves selection and existing results; empty state suggests refining or clearing system.
- Selected token stays recognizable while searching. Editing its text clears the hidden draft identity; never send an old ID under a new label.
- Clear removes only draft terminal, returns focus to input and waits for Apply.
- Touch-friendly options, bounded scrolling list and wrapping labels. Do not truncate the only disambiguating context.
- Stop selector events triggering parent market autosubmit. Give the two responsive form copies unique input/list/option IDs or render one form, synchronize canonical state and prevent duplicate submitted values.
- Progressive fallback may use a small server-rendered terminal search/results page; do not use an 830-option fallback select.

| Alternative | Tradeoff |
| --- | --- |
| Require system then terminal search | Smaller scope but prevents finding a terminal whose system is unknown; keep system narrowing optional |
| Native/full-catalog searchable select | Simpler coding, but 830 entries, duplicated labels and up to 96-character context are poor panel/mobile ergonomics. Even 135 eligible entries can grow; measurements do not justify full-catalog delivery |

## 7. Filter interactions and URL contract

**Recommended Apply contract:** draft changes commit only on Apply. This preserves the requested explicit workflow but deliberately removes observed implicit auto-apply. It avoids applying partial search text and intermediate terminal/system states. Confirm this in M1; an auto-apply alternative needs a separately specified commitment boundary.

| Interaction | Recommendation |
| --- | --- |
| Star System + terminal | System narrows suggestions; selecting globally leaves All systems, with actual host in terminal context |
| System changes incompatibly | Clear draft terminal with visible/live announcement. Applied results stay until Apply. Compatible/All systems retains it |
| Crafted incompatible URL | Preserve constraints as an intersection; show selected terminal, mismatch warning and empty groups with clear-system action. Never silently broaden |
| Commodity, market Search, Location Type | AND with terminal and existing filters. Incompatibility gives empty groups. Selector search remains independent |
| Player Action Any | Each group applies its predicate to the common filtered relation |
| Player Action Buy | Existing buy restriction applies first; Buy contains those rows, Sell their both-qualified subset |
| Player Action Sell | Sell restriction first; Buy contains their both-qualified subset, Sell those sell rows |
| Player Action Both | Same-row intersection first; same qualifying rows can appear under both headings |
| Explanatory action text | “Restricts matching offers. Each heading shows the actions supported by those offers.” Support on both sides is not two positive quotes |
| Apply | Validate canonical params, reset page/buy_page/sell_page to 1, GET /market with committed filters |
| Clear terminal | Preserve other draft filters; Apply returns to legacy ungrouped feed |
| Reset | GET / without filter params; clear applied/draft/page state |
| No terminal | Existing ungrouped feed/trade_mode and 50-row legacy page parameter |
| Invalid/deleted/unknown/duplicate external ID | Visible invalid/unavailable selection and empty results with clear action; never remove invalid ID and show all terminals |
| Valid terminal loses market rows | Keep resolved identity recognizable; show two empty groups |
| Share/refresh | `/market?terminal_api_id=29&...&buy_page=1&sell_page=2` reconstructs everything; no localStorage/prior search dependency |
| Back/forward | Restore canonical controls, selected context and both pages in both responsive copies |
| Paging with uncommitted drafts | Links use **applied server params**. Result navigation restores those controls and discards drafts consistently |

This preserves current Player Action row semantics and always shows both required headings, rather than silently discarding the filter. Hiding one heading would be a different contract.

Primary navigation recommendation: normal GET with Turbo Drive for Apply/Reset so controls, results and address bar update together; keep market_results frame paging with explicit history promotion and restoration synchronization. Reinitializing dashboard/map on Apply is the tradeoff for simpler canonical state; test map/details behavior. Frame-only Apply is viable only with explicit URL promotion and canonical form synchronization, which current configuration lacks.

Strictly parse identity; do not accept `29junk` through to_i. Normalize enum/page inputs and document default behavior. Resolve current selected identity separately from search eligibility so a lost last offer does not erase its label.

## 8. Grouped rendering, pagination and live behavior

Keep one outer market_results frame. Show terminal canonical name, code, host/system, source/snapshot timing and clear/refresh actions above groups. Always render **Buy then Sell**, even when empty. Each heading shows “N matching offers; showing X–Y”, relevant quote/stock/capacity text, group-specific empty state and independently labelled paging.

Mandatory sequence:

```ruby
# Proposed structure; not implemented:
base = MarketQuery.new(canonical_filters).scope
# Includes terminal and all filters, including the existing trade_mode restriction.
buy_scope = base.player_can_buy
sell_scope = base.player_can_sell
# Count whole scopes, then stable-sort, then offset/limit each independently.
```

Do not split the old loaded 50-row page. Do not reuse API commodities, which materializes its full relation and has different availability/serialization semantics.

- 50 per group; maximum 100 rendered offer rows. buy_page/sell_page independent; each link preserves the other and applied filters.
- Counts are full matching **offers**, not unique commodities or loaded rows. Overlap explains sums above unique rows (GrimHEX 14 + 89 > 101).
- Keep sort/direction whitelist in each group, default updated DESC, stable PK tie-breaker, NULLS LAST. In normalized quote sorting treat unsupported/missing-side quotes as missing.
- Clamp malformed pages to 1 and excess pages to last nonempty page, or 1 when empty; handle import between requests.
- Eager-load optional host/commodity; resolve terminal once; never query terminals per row.
- New query service should return canonical filters, selected context and both groups/count/page metadata. Two counts and two bounded row queries are adequate initially. Optimize conditional counts only if measured.

### Stream correctness

Current replace target cannot update two group copies. Use IDs such as market_buy_row_123 and market_sell_row_123, keeping original IDs in legacy mode.

Recommend treating existing market_prices messages as **invalidations** in terminal mode and re-querying the applied frame, coalesced/throttled, rather than inserting the ungrouped replacement partial. Recompute membership/count/order/pages together. Prototype the adapter against installed Turbo in M3; reject stale frame responses and preserve focus/scroll. At most one refresh per second; defer disruptive updates during keyboard interaction and show “Updates available”. Never apply drafts during refresh.

Include explicit Refresh and as-of timing. Existing bulk tick/import paths suppress row messages, so do not claim every-tick freshness. Automatic tick polling or new importer invalidations are separately scoped improvements, not required for correct Apply/Refresh results. Preserve legacy stream behavior. Snapshot-only terminal results are simpler but intentionally change update behavior and require an explicit choice.

## 9. Indexes and performance findings

Observed production pg_indexes match relevant schema:

- Terminal: PK, location_name; **no api_id index or uniqueness**.
- ProductionFacility: PK, unique api_id, location_name; **no id_terminal index**.
- Location: unique name, parent_name, nonunique api_id.
- Commodity: PK, nonunique api_id; no name index/uniqueness.
- No terminal/host-name/commodity-name foreign keys (`db/schema.rb:710-736`).

Read-only warm-cache EXPLAIN ANALYZE, not application benchmarks:

| Query | Execution / planning | Plan |
| --- | --- | --- |
| Terminal 27 Buy predicate, updated DESC/id, LIMIT 50 | **0.730 / 0.115 ms** | Sequential scan 2,590 facilities, 14 kept/2,576 removed; sort; 609 shared-hit blocks, zero read blocks |
| %gateway% name/code/nickname/host/system, host join, market EXISTS, name/api_id, LIMIT 21 | **3.013 / 1.071 ms** | Scans 830 terminals, 671 locations, 2,590 facilities; hashes market IDs; returns 14; 658 hits, zero reads |

These limited-field samples omit rendering, menu/settings queries, network, full token-search logic and full recommended eligibility. They do not establish p95/cold-cache performance. A separate richer plan with largest-terminal lookup was inspected but is not the simple baseline above.

**Likely migrations:** unique terminal api_id index for identity and facility id_terminal index for filtering/EXISTS growth. Fresh duplicate audit and safe handling of concurrent import are prerequisites. Use online index creation with nontransactional migration as appropriate. No terminal/commodity unique composite: distinct offers may be valid. Today's ~3 ms substring sample does not justify installing trigram extensions or indexing every search field.

Proposed acceptance budgets, **not yet tested**:

- At most 20 lookup options, has_more, JSON ≤20 KiB; no full catalog in HTML.
- One lookup in flight; stale responses never win; typing burst emits only final debounced search after idle.
- Query-service grouped load ≤8 SQL statements including identity/counts/rows/shared association preloads, constant for 1 vs 100 rows. Measure whole-request settings/menu overhead separately.
- On a recorded preview machine, warm p95 server time <150 ms lookup / <300 ms grouped feed over ≥30 samples; separately report Chrome network/render time.
- Isolated synthetic 10x/100x scale: bound payload/DOM/allocations, inspect EXPLAIN buffers/loops, worst terminal and substring/no-match/system queries. No production seeding.
- No N+1 or join fanout. Consider read-only repeatable-read query transaction if concurrent imports cause count/list inconsistency.

## 10. Likely files, endpoints and tests

“New” entries are proposed names, not existing implementation.

| File | Expected impact |
| --- | --- |
| `config/routes.rb` | New GET /market/terminals; preserve root/market |
| `app/controllers/star_trader_controller.rb` | New params, validation, selected context, grouped/legacy loading |
| New `app/queries/market_query.rb` | Common filtering/sorts, full-scope grouping/count/page |
| New `app/queries/terminal_search_query.rb` | Eligibility, bounded contextual search/ranking/identity |
| New `app/controllers/market_terminals_controller.rb` | Read-only JSON serializer/endpoint; assess inherited menu/settings overhead |
| `app/models/terminal.rb`, `production_facility.rb` | Explicit external-ID relationship if useful; reuse player scopes/prices |
| `app/models/location.rb` | Correct name-key terminal inverse if used; no hierarchy redesign |
| New `db/migrate/*_index_terminal_market_identity.rb`, `db/schema.rb` | Unique terminal api_id and facility id_terminal indexes; no catalog rewrite |
| `app/views/star_trader/_filters.html.erb`; `market_filters_controller.js` | Staged Apply, clear/system rules and responsive IDs |
| New `_terminal_selector.html.erb`; `terminal_selector_controller.js`; `app/javascript/controllers/index.js` | Accessible combobox, bounded transport, manifest registration |
| `index.html.erb`, `_market_results.html.erb`, new `_market_group.html.erb` | Context, ordered groups/counts/pages, full/frame responses |
| `_market_row.html.erb`, `star_trader_helper.rb`, `market_board_controller.js` if needed | Group IDs/action text, optional associations, retained map/details |
| New `market_results_controller.js` or narrow existing extension | Applied URL/history, invalidation/refresh/focus |
| `test/controllers/star_trader_controller_test.rb` | Terminal/filter/group/page/invalid/URL cases |
| New `test/controllers/market_terminals_controller_test.rb` and query tests | Bounds/ranking/eligibility/identity/query counts |
| `test/models/production_facility_test.rb` | Predicate/price parity, two group copies and stream behavior |
| `test/services/admin/data/terminals_importer_test.rb`, `facilities_populator_test.rb` | Retain mapping/identity tests; extend if constraints/associations affect imports |
| New `test/system/terminal_market_test.rb` | Chrome keyboard/async/mobile/history/Apply/stream checks |
| `test/controllers/api/commodities_controller_test.rb`, `test/services/trade_service_test.rb` | Regression boundary: no API perspective reversal or execution change |

Partial/controller/helper filenames without full paths in this table are under `app/views/star_trader`, `app/javascript/controllers` or `app/helpers` as appropriate. API, tick/orbital engine, imports and trade execution need no feature changes by default.

Focused validation:

1. **Identity:** same-name terminals within/across hosts/systems, duplicate code, internal PK≠external ID, null/nonpositive/duplicate external IDs, missing host; no name fallback/sibling leakage.
2. **Semantics:** buy-only Bezdek, sell-only, synthetic valid both-price row, stock/status-only missing price, zero stock/full capacity, missing Commodity, negative-local parity; decimal precision.
3. **Filters:** system changes/forged mismatch, q/commodity/type ANDs, Any/Buy/Sell/Both, selected context when groups empty.
4. **Search:** caps, blank/too-long/Unicode/wildcards, bound tokens/SQL, optional global search, ranking/duplicates, loading/error/retry; controlled delayed fetch/JSON responses cannot win after newer search/clear/disconnect.
5. **Groups:** >50 rows on **each** side, empty sides, full counts/overlap, independent pages, stable ties, out-of-range pages, import between requests.
6. **URL/workflow:** search/selection does not apply, Enter does not submit, Apply resets pages, terminal-only clear, Reset, both forms, direct URLs/refresh/back/forward.
7. **Chrome accessibility/mobile:** keyboard completion/clear, Escape/Tab/focus, screen-reader labels/announcements, unique IDs, 320/375 px layout/touch/scroll, hidden responsive copies, reachable results after Filters, no overflow.
8. **Streams:** both group copies recomputed, membership/count/order updated, no ungrouped partial injection, bounded bursts, stale rejection, focus/scroll; explicit Refresh reflects suppressed bulk updates.
9. **Efficiency/regressions:** bounded payload/query count, no N+1/catalog preload, safe sort params, optional associations, read-only endpoint, map/details and legacy mode.

`test/application_system_test_case.rb:4` uses Selenium **:chrome**. `test/system` contains only `.keep`; historical test:all results do not constitute combobox coverage.

During implementation use `bin/codex_test` with a freshly verified isolated database, then appropriate expanded checks. It performs bundle install and **db:prepare**, so was deliberately not run in discovery. Inspect task side effects before builds. Verify/pin official installed Google Chrome and keep browser commands/reports Chrome-only. No feature tests or browser checks are claimed passed here.

## 11. Access limitations and remaining choices

Access outcomes:

- Initial sandbox WSL launch denied; approved read-only WSL execution then succeeded.
- Default development socket authentication failed (“no password supplied”); sudo required a password. No auth/role changes.
- Existing profiles were parsed without printing secrets, then queried with pg: local preview had **0 terminals, 0 facilities, 216 locations**; local test had all three zero. They are not populated qualification datasets.
- Existing Heroku login provided fresh app/release/process metadata and read-only production catalog access.
- Rails was not booted. `config/initializers/rabbitmq.rb` connects brokers outside test; `tick_bootstrap.rb` can enqueue recovery; `Tick.instance` uses first_or_create (`tick.rb:30-31`). Docker entrypoint can prepare DB. Direct pg avoided these paths.
- No rendered production UI/screenshot, Chrome accessibility, HTTP latency, asset build, upstream API fetch or import execution inspected. Full deployment slug SHA not freshly retrieved.

Choices to settle in M1:

| Choice | Recommended default | Alternative consequence |
| --- | --- | --- |
| Missing-price rows | Preserve predicates, show unavailable quote | Price-only removes 82 side memberships and currently empties Both |
| Player Action | Existing row restriction, then both groups | Heading-only filtering changes Both semantics and can hide required group |
| Apply | Explicit staged Apply | Auto-apply requires specified commitment boundary |
| Eligible terminals | Host + market/action rows; no age/visible cutoff | All-terminal adds 695 no-market entries; visible gate removes one market terminal; age cutoff removes all |
| Refresh | Row-message invalidation plus explicit Refresh | Snapshot-only intentionally changes existing update behavior |
| Navigation | Full-page GET Apply; frame/history paging | Frame-only Apply needs robust canonical synchronization but preserves dashboard initialization more closely |

These recommendations are not blockers to discovery. Confirm before treating them as implementation requirements. Repository/database evidence cannot decide product policies.

Other risks: no current terminal API uniqueness; facility PK churn on import; stale source masked by gameplay time; four missing commodity associations; context/code can still collide; imports can change pagination; global broadcasts may drive excess refresh; two form copies complicate identity/focus/state. Upstream ID reuse and exact external status semantics remain unverified. No unrelated data repair is authorized.

## 12. Milestones and release plan

| Milestone | Work and exit evidence |
| --- | --- |
| **M1 — Contract, identity, query foundation** | Revalidate branch/HEAD/worktree and production drift; settle six choices. Implement strict identity/common query/group scopes/stable sorts, explicit associations as needed, safe index migrations. Tests prove PK/name distinction, duplicate safety, action parity and full-scope counting |
| **M2 — Bounded selector** | Endpoint/ranking/caps, contextual accessible combobox, staged identity/system/clear. Requests prove payload/eligibility/SQL safety; Chrome proves keyboard/async/IME/mobile; no catalog preload |
| **M3 — Grouped feed/navigation** | Buy then Sell, unique IDs, quote/empty/count states, separate pages, canonical history, Apply/Reset and legacy compatibility. Prototype stream invalidation/focus/coalescing. >50-per-side tests prove pre-pagination grouping |
| **M4 — Qualified candidate** | Focused/required suite on isolated DB, meaningful Chrome checks, terminating asset build, query/payload/p95/scale evidence. Review exact integrated SHA, migrations and rollback; retain explicit gaps |
| **M5 — Authorized production release** | Fresh app/domain/database/release/slug/source/process preflight; identity/index/pending-migration audit. Deploy exact qualified SHA through PR/Heroku Git process; explicitly execute appropriate approved index migration process. Verify assets/processes plus read-only and Chrome selection/groups/counts/pages/URL/error checks; no import/test trades |
| **M6 — Closeout** | Record release/SHA/schema/Chrome/performance evidence and deferred issues; rollback candidate preserves compatible schema and current orbital/travel rules. Successful push alone is not completion |

Established process: `STARTRADER_TRAVEL_TIMING_RELEASE.md:51-59` and current Heroku remote/Procfile show qualified PR integration, exact-SHA Heroku Git deploy, release/slug and web/worker verification, then bounded read-only and Chrome checks. No checked-in CI/deploy workflow or Procfile release command was discovered. Procfile has web/worker only; do not assume Heroku Git auto-runs migrations. Docker entrypoint's db:prepare is a different path.

Likely release: Ruby/ERB/importmapped Stimulus, CSS/digested assets and two additive index migrations. No new tables/backfill/import, orbital/tick/settings changes or production trades required. Reconcile existing pending migrations, especially `20261024170000_widen_cargo_unit_prices.rb` from later regression repair, documented as locally qualified but not deployed. Do not accidentally combine unrelated migrations.

Rollback: record immediate prefeature release and compatible source; revert feature code/assets while leaving additive indexes in place. Drop indexes separately only if necessary. Preserve already deployed cargo-price widening, orbital-v3 anchored schedule and travel timing. Old v166/v167 recipes are not automatically safe for a later release. Do not restore DB, reimport, recalculate journeys or reset ticks for a UI rollback. Handle failed/invalid concurrent indexes with a specific inspected recovery plan, not blind retries.

## 13. Reproducible queries and next executable milestone

Use the secure existing credential path without logging credentials; direct pg with read-only connection options, never Rails preparation. Representative audit:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '10s';
SET LOCAL lock_timeout = '1s';
SHOW transaction_read_only;

SELECT count(*) FROM terminals;
SELECT count(*) FROM production_facilities;
SELECT count(*) FROM terminals t
WHERE EXISTS (SELECT 1 FROM production_facilities f
              WHERE f.id_terminal = t.api_id);

SELECT lower(trim(name)), count(*), count(DISTINCT location_name)
FROM terminals GROUP BY lower(trim(name)) HAVING count(*) > 1;

SELECT api_id, count(*) FROM terminals
WHERE api_id IS NOT NULL GROUP BY api_id HAVING count(*) > 1;

SELECT l.star_system_name, count(*),
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM production_facilities f WHERE f.id_terminal=t.api_id))
FROM terminals t LEFT JOIN locations l ON l.name=t.location_name
GROUP BY l.star_system_name;

SELECT count(*) FROM production_facilities f
WHERE f.id_terminal IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM terminals t WHERE t.api_id=f.id_terminal);

SELECT count(*) FROM production_facilities
WHERE id_terminal IS NULL AND nullif(location_name,'') IS NOT NULL;

SELECT id_terminal, id_commodity, commodity_name, count(*)
FROM production_facilities
GROUP BY id_terminal,id_commodity,commodity_name HAVING count(*) > 1;

SELECT tablename,indexname,indexdef FROM pg_indexes
WHERE schemaname='public'
  AND tablename IN ('terminals','production_facilities','locations','commodities');
ROLLBACK;
```

Action counts use literal predicates in section 5; lengths use char_length/percentile_cont; source age uses to_timestamp(date_modified), separately from updated_at. Section 9 records the bounded plan shapes and timings; rerun against changed scale before relying on them.

**Next executable milestone: M1.** Start from the tracked baseline, preserve unrelated untracked work/worktree, confirm the policy table, and implement identity/query/index tests in an isolated environment. This discovery request does not authorize implementation.

To turn this into a concrete Codex/Claude multi-milestone playbook, carry forward: accepted policy table, exact parameter/JSON/partial contracts, migration/concurrency gates, a populated isolated fixture strategy (current profiles lack market data), per-milestone file ownership and acceptance commands, Chrome binary/viewport/accessibility scenarios, measured performance budgets, stream prototype evidence and a freshly verified exact production source/schema baseline. Catalog measurements and terminal join/price evidence needed to start that playbook are now established.
