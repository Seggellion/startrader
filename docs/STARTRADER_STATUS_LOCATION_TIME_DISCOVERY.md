# StarTrader discovery: status synchronization, location tracking, admin user interface, timestamp standardization

Date: 15 November 2026
Owner: Dustin Hill
Executor: Claude Code in the StarTrader repository
Repository state inspected: branch `claude/startrader-discovery-fa1f6d` at `4f42a56` (clean working tree)
Document status: **Discovery complete. No application code, schema, data, or deployment was changed.**
Related documents: `docs/STARTRADER_TERMINAL_FILTER_DISCOVERY.md` and `docs/STARTRADER_TERMINAL_FILTER_PLAYBOOK.md` (document conventions and the terminal/market subsystem), `STARTRADER_ORBITAL_CALIBRATION_DISCOVERY.md` and `STARTRADER_ORBITAL_RATE_CORRECTION.md` (orbital clock, simulated seconds, catalog identity), `STARTRADER_TRAVEL_TIMING_RELEASE.md` (1 Gm/tick travel policy), `STARTRADER_REGRESSION_REPAIR.md` (the October 2026 suite repair referenced in F-07). This document does not restate those.

### Evidence discipline used in this document

* **Confirmed** means I read the code path end to end, or an existing test in this repository asserts the behaviour. Confirmed findings cite a file and line, or a test name and line.
* **Probable** means the code supports the conclusion but the trigger depends on data or client payloads I cannot observe from this checkout.
* **Unresolved** means I could not determine the answer from the repository alone.

**Tests actually executed: none.** `bin/codex_db_doctor` reports that this session's PostgreSQL socket requires a password for the active Linux user (`fe_sendauth: no password supplied`), so `bin/codex_test` could not prepare a test database. I did not reuse the credentials found in other local `.env.*` profiles to reach a database. Every behavioural claim below is therefore from source reading, from assertions already written into the committed test suite, from `git log`/`git show`, or from the one database-free Ruby probe recorded in §6.3. Tests named in §12 are **proposed**, not run.

---

## 1. Executive summary

### 1.1 The four problems

| # | Reported problem | What the repository actually shows |
|---|---|---|
| 1 | `/api/status` stopped synchronizing player/ship data | The synchronization code is present, reachable, and covered by roughly 60 committed tests. It is not missing. It has **four distinct hard-fail or mis-target paths** that each end a status request without writing anything: an unresolvable location name returns HTTP 400 (F-18); a case-colliding `player_name` returns HTTP 422 before the write transaction opens (F-05); an unknown or case-variant `shard_uuid` silently creates a *second* `Shard` and `ShardUser`, so writes land on a record nobody is looking at (F-04); and a legacy caller that sends `shard_uuid` without ship fields is routed into the new path and rejected (F-19). |
| 2 | Admin user view needs rebuilding | `app/views/admin/users/show.html.erb` renders **no `ShardUser` record, no shard membership, and no player location at all**, and shows `users.wallet_balance` instead of the authoritative `shard_users.wallet_balance` (F-09). It is also the only dark-themed page inside a `bg-gray-100` admin layout (F-21). |
| 3 | Timestamps should standardize on Unix seconds | The travel contract exposes **no absolute time whatsoever** — only `departure_tick`, `arrival_tick`, `current_tick`, and second-valued durations. There is nothing to convert and nothing currently broken by timezones in the travel path. The real gaps are two contradictory countdowns in one status response for interdicted ships (F-13), unlabelled UTC `strftime` in admin views, one hardcoded Pacific conversion, and the absence of any absolute arrival instant a client could use to survive a tick-chain stall. |
| 4 | Jump does not update `last_location` | **Confirmed, and it is the clearest defect in this report.** `GateTravelService` is the only travel writer in the codebase that never touches `ShardUser`; `grep` over `app/services/gate_travel_service.rb` finds no `update_current_location!`. It moves `user_ship.location_name` to the departure gateway (`gate_travel_service.rb:137`) and leaves the player behind. The arrival processor's guard then *refuses* to fix it, because the player's recorded location no longer equals `travel.from_location_id` (`ship_travel_arrival_processor.rb:43-51`). The repository's own test suite asserts the ship teleport and asserts nothing at all about the player (`test/controllers/api/gate_travel_controller_test.rb:179-194`). |

### 1.2 Do they share a common cause?

Problems 1, 2 and 4 share one. Problem 3 does not.

**The shared cause is that `ShardUser.last_location` has no owner.** Seven call sites write it, each with its own policy, and nothing arbitrates between them:

| Writer | Policy | Authority |
|---|---|---|
| `TradeService.authoritative_status_sync!` (`trade_service.rb:111`) | overwrite unconditionally | client |
| `TradeService.update_status_location!` (`trade_service.rb:253`) | overwrite unconditionally | client |
| `TravelService#call` (`travel_service.rb:56`) | set to journey **origin** on departure | server |
| `ShipTravelArrivalProcessor` (`ship_travel_arrival_processor.rb:49`) | set to destination **only if** current value equals journey origin | server, conditional |
| `ShipAvailability#ensure_player_location_from_ship` (`ship_availability.rb:74`) | copy from ship when player is unknown | repair |
| `Api::ShipTravelController#initialize_unknown_locations_from_request!` (`ship_travel_controller.rb:634`) | seed from travel request when both are unknown | repair |
| `Api::ShardUsersController#set_shard_user` (`shard_users_controller.rb:49`) | overwrite with Minecraft `{x,y,z}` | **dead code** — references the removed `users.minecraft_uuid` and `users.email` columns |
| `GateTravelService` | **never writes it** | — |

The arrival processor is the only *conditional* writer, and its condition is an equality test against a value that four unconditional writers can change at any moment. That single design choice produces all three symptoms: the Jump never arms the condition (problem 4), a status call during flight disarms it (problem 1), and because nothing is observable the operator cannot see which of the two values diverged (problem 2).

Problem 3 is a separate, lower-severity consistency issue. It is worth fixing, but it is not causing problems 1, 2 or 4, and attempting it first would delay them.

### 1.3 Recommended direction

1. **Give `last_location` a single owner and an explicit authority model.** Server-authoritative state (an active or interdicted `ShipTravel`) wins; client observations are accepted only when no journey is in flight. Route every write through one service instead of seven call sites.
2. **Make the Jump a first-class travel initiation**: either refuse to jump from a gateway the ship is not at, or move ship *and* player together when it does. Do not special-case the arrival guard around it.
3. **Make the state observable before changing more of it.** The admin rebuild is not cosmetic work here — it is the instrumentation that tells the operator whether the repair worked. It needs no schema change to show a useful diagnostics panel.
4. **Keep timestamps last and narrow**: additive `*_at_unix` fields beside the existing tick fields, no change to tick semantics, no change to `arrival_tick = 0`.

A credible first milestone is a **read-only** one: ship the admin user view and a `last_location` audit, so the fix in milestone 2 can be verified against observed production state rather than assumed state. See §13.

### 1.4 Verdict

**CONDITIONAL.** Objectives 1, 2 and 4 are understood well enough to write an implementation playbook now. Objective 3 needs two owner decisions first (precision/fractional seconds, and whether the external StarBitizen client can accept additive response keys), and objectives 1 and 4 need two policy decisions that are genuinely the owner's to make (what a status location report means during flight, and whether `/api/status` may keep creating shards and stealing ship rows). All six are listed with recommendations in §14; four of them I can defend from repository evidence, two require the owner.

---

## 2. Architecture inventory

### 2.1 Routes (`config/routes.rb`)

| Route | Target | Auth | Notes |
|---|---|---|---|
| `POST /api/status` | `Api::TradesController#status` (`routes.rb:105`) | `X-Secret-Guid` | **This is the status endpoint.** It lives in the *trades* controller. |
| `POST /api/buy`, `POST /api/sell` | `Api::TradesController#buy`/`#sell` | **skipped** (`trades_controller.rb:5`) | `skip_before_action :authenticate_secret_guid!, only: [:buy, :sell]` |
| `POST /api/travel`, `POST /api/ship_travel` | `Api::ShipTravelController#create` | skipped except destroy paths | normal intra-system travel |
| `POST /api/gate_travel` | `Api::GateTravelController#gate_travel` | `X-Secret-Guid` | **the Jump** (inter-system jumpgate) |
| `POST /api/user_ships/:guid/interdict`, `/resume`, `/destroy` | `Api::ShipTravelController` | guid auth on `destroy` only | |
| `DELETE|POST /api/cancel` | `Api::ShipTravelController#destroy` | `X-Secret-Guid` | |
| `GET /api/location/:user_ship_id` | `Api::ShipTravelController#location` | skipped | |
| `POST /api/set_tick`, `POST /api/increment_tick` | `Api::TickController` | **none** | F-10 |
| `POST /api/shard_users/:id/adjust_stats` | `Api::ShardUsersController` | Bearer `britannia_api_token` | dead: `set_shard_user` references removed columns |
| `POST /api/user_ships/:user_ship_id/move` | `MovesController#create` | none | contains a live `byebug` (F-23) |
| `GET /users` | `UsersController#index` | **none** | renders every `User` row as JSON (F-11) |
| `GET /users/:id/edit_minecraft_uuid`, `PATCH .../update_minecraft_uuid` | `UsersController` | none | **actions do not exist** |
| `/admin/users`, `/admin/users/:id` | `Admin::UsersController` | session + `require_admin` | objective 2 |
| `/admin/shard_users` | `Admin::ShardUsersController` | session + `require_admin` | **not linked from the admin sidebar** |

### 2.2 Controllers

| Path | Relevant methods | Role |
|---|---|---|
| `app/controllers/api/trades_controller.rb` | `status` (148), `normalized_status_payload` (241), `status_payload_sources` (267), `first_present_param` (286) | status entry point; flattens top-level / `trade[...]` / raw-JSON payload shapes |
| `app/controllers/api/base_controller.rb` | `parse_json_request` | `ActionController::API`; sets `@json_payload` |
| `app/controllers/concerns/secret_guid_auth.rb` | `authenticate_secret_guid!` | SHA-256 constant-time compare against `Setting.get('secret_guid')` |
| `app/controllers/api/ship_travel_controller.rb` | `create` (13), `location` (128), `interdict_by_guid` (186), `resume_by_guid` (209), `destroy` (339), `process_due_arrival_for` (505), `initialize_unknown_locations_from_request!` (616), `resolve_current_location_for_travel` (638), `travel_in_progress?` (700) | normal travel, interdiction, cancel |
| `app/controllers/api/gate_travel_controller.rb` | `gate_travel`, `gateway_name_param` | Jump; accepts `gateway_name`, `destination_gateway`, `destination`, `to_gateway`, `to_location` as aliases |
| `app/controllers/api/ships_controller.rb` | `deliver_ship` (62), `dump_cargo` (32) | `deliver_ship` moves `location_name` with no travel guard and no player sync (F-20) |
| `app/controllers/admin/users_controller.rb` | `index`, `show`, `set_user` (28) | `includes(user_ships: [:ship, :user_ship_cargos, {active_travel: :to_location}])`; **no `shard_users` preload** |
| `app/controllers/admin/shard_users_controller.rb` | `index`, `edit`, `update`, `shard_user_params` | permits `wallet_balance, karma, fame, murder_count`; **cannot view or edit `last_location`** |
| `app/controllers/admin/application_controller.rb` | `authenticate_user!`, `require_admin` | session `user_id` + `user_type` enum |

### 2.3 Services

| Path | Relevant methods | Role |
|---|---|---|
| `app/services/trade_service.rb` (1415 lines) | `status` (17), `status_by_ship_guid` (67), `authoritative_status_sync!` (91), `find_or_create_status_shard!` (151), `find_or_create_status_user!` (163), `find_or_create_status_ship!` (188), `assign_authoritative_status_user_ship!` (196), `resolve_status_location!` (228), `update_status_location!` (242), `legacy_status` (265), `status_response_for` (389), `status_availability_for` (456), `active_status_travel` (481), `status_travel_payload` (489), `latest_relevant_ship_travel` (509), `update_status_wallet_balance!` (538), `find_trade_shard` (1304) | all status behaviour plus buy/sell |
| `app/services/star_trader_ship_sync.rb` | `call`, `resolve_shard!`, `find_or_create_user_and_shard_user!`, `validate_user_ship_ownership!` | identity resolution for `/api/travel`; **strict** shard lookup and **strict** ownership, unlike status |
| `app/services/travel_service.rb` | `call` | normal travel creation; **sets player location to the origin** (line 56) |
| `app/services/gate_travel_service.rb` | `call` (26), `resolved_origin_gateway` (86), `validate_gateway_location!` (80), `target_star_system_from` (102), `create_gate_travel!` (118) | the Jump; **never writes `ShardUser`** |
| `app/services/ship_travel_arrival_processor.rb` | `call`, `arrival_status`, `update_player_location_if_travel_origin_matches!` (43) | the only server-authoritative player-location writer on arrival |
| `app/services/ship_availability.rb` | `status`, `validate_usable!`, `in_transit?`, `process_due_arrival!`, `ensure_player_location_from_ship` (72) | ship/player co-location gate |
| `app/services/location_resolver.rb` (422 lines) | `resolve`, `resolve_exact`, `resolve_in_star_system`, `resolve_pair_in_star_system`, `ranked_match` (212) | name → `Location`; `ranked_match` iterates `Location.find_each` in Ruby |
| `app/services/orbital_state.rb` | `current_tick!`, `clock_metadata`, `resolve` | catalog identity + simulated clock |
| `app/services/travel_time_calculator.rb`, `lib/travel_timing.rb` | `calculate`, `duration_ticks`, `metadata` | 1 Gm/tick, minimum 2 ticks |
| `app/services/tick_runner.rb` | `run_once!`, `with_tick_lock` | advisory-locked tick advance |
| `app/services/rabbitmq_sender.rb` | `send_ship_report` | arrival event: pipe-delimited, carries `departure_tick` and `arrival_tick`, **no absolute time** |

### 2.4 Models, jobs, views, tests

* **Models**: `app/models/user.rb`, `shard_user.rb` (`JsonStoreCoder` 7, `store :last_location` 21, `current_location_name` 75, `current_location` 83, `update_current_location!` 87), `user_ship.rb` (`active_travel`/`ship_travel` has-ones, `infer_shard_user`, `shard_user_consistency`), `ship_travel.rb` (scopes `active`/`in_flight_now`/`interdictable_now_sql`, `interdict!`, `resume!`, `due_for_arrival?`, `cleanup_after_arrival!`), `shard.rb`, `location.rb`, `tick.rb`, `tick_control.rb`.
* **Jobs**: `app/jobs/tick_job.rb` (self-chaining), `tick_watchdog_job.rb` (30 s recovery), `ship_arrival_job.rb` (runs each tick; correctly excludes `arrival_tick: 0`).
* **Channels**: `app/channels/tick_channel.rb` broadcasts `{type, tick, seconds_per_tick}` + orbital clock metadata; `app/javascript/controllers/star_system_controller.js:29-34` consumes integer ticks only.
* **Views**: `app/views/admin/users/show.html.erb` (207 lines, objective 2), `admin/users/index.html.erb`, `admin/shard_users/index.html.erb`, `admin/user_ships/edit.html.erb` (**the newest and most complete admin detail page**, 2026-06-30 `4021768`), `app/views/layouts/admin.html.erb`, `admin/shared/_side_bar.html.erb`.
* **Tests**: `test/controllers/api/trades_controller_test.rb` (946 lines, ~30 status tests), `test/services/trade_service_test.rb` (824 lines, ~30 status tests), `test/controllers/api/ship_travel_controller_test.rb` (1588), `test/controllers/api/gate_travel_controller_test.rb` (414), `test/jobs/ship_arrival_job_test.rb` (189), `test/models/shard_user_test.rb` (209), `test/services/travel_service_test.rb` (112), `test/controllers/admin/access_test.rb` (20). Helpers: `test/support/integration_sign_in.rb` (`sign_in_admin`), `test/support/orbital_fixtures.rb`, `test/support/no_real_broker.rb`.
* **Rake**: `lib/tasks/ship_locations.rake` — `ship_locations:backfill_player_locations` already exists and backfills `last_location` from the newest ship location, skipping records that already have one. Reusable for the repair.

---

## 3. Current data model

### 3.1 `users` (`db/schema.rb:692-710`)

`uid` (not null, unique), `provider`, `username`, `twitch_id`, `user_type` (enum `admin: 0, player: 1`), `first_name`, `last_name`, `avatar`, `country`, `last_login`, `global_inventory` json, `purchased_items` json, `wallet_balance` decimal(15,2), timestamps.

Indexes: `index_users_on_uid` unique; `index_users_on_lower_username_unique` — **unique on `lower(username)`** where username is non-null and non-empty (`db/migrate/20260708120000`).

Validations (`app/models/user.rb`): `username` presence + uniqueness `case_sensitive: false`; `twitch_id` presence; `uid` presence + uniqueness.

* There is **no `last_activity`** column. `last_login` is the only activity-ish field and is written only by the OAuth callback.
* There is **no `minecraft_uuid`** and **no `email`** (`db/migrate/20250304020522_remove_email_from_users.rb`), although three code paths still reference them.
* `users.wallet_balance` exists but is **not** the gameplay wallet. The game reads and writes `shard_users.wallet_balance`.
* `User#active_ship` is defined twice — once as `has_one :active_ship, -> { order(updated_at: :desc) }` and once as an instance method that re-queries. The method wins, so preloading `active_ship` is always discarded.

### 3.2 `shard_users` (`db/schema.rb:418-435`) — the player record

`user_id` (not null), `shard_id`, `karma`, `fame`, `murder_count`, `currency` json `{}`, `inventory` json `{}`, `stats` json `{}`, **`last_location` jsonb `{}`**, `shard_name`, `wallet_balance` bigint `0`, timestamps.

Indexes: `index_shard_users_on_user_id_and_shard_id_unique` unique (`db/migrate/20260630120000`), plus single-column indexes. FKs to `users` and `shards` are `validate: false`.

* **There is no `current_location` column.** `ShardUser#current_location` (`shard_user.rb:83`) is a derived reader: `Location.find_by(name: current_location_name)`. The brief's §C lists `ShardUser.current_location` as a stored field; it is not one. Every `shard_user.current_location` call is one extra `locations` query.
* **There is no synchronization timestamp.** `updated_at` is the only proxy, and it is bumped by wallet writes, karma writes, and location writes alike.
* `last_location` is the **only** location field on the player.

`last_location` payload shape written by `update_current_location!` (`shard_user.rb:87-98`):

```ruby
payload = (last_location || {}).dup       # pre-existing keys are preserved, never deleted
payload["id"]                = location.id
payload["name"]              = location.name
payload["location_name"]     = location.name
payload["star_system_name"]  = location.star_system_name
payload["classification"]    = location.classification
update!(last_location: payload)
```

`current_location_name` (`shard_user.rb:75-81`) reads `name`, then `:name`, then `location_name`, then `:location_name`. It reads **no coordinate keys**. A legacy Minecraft `{x,y,z}` payload therefore yields `nil`, which means "player location unknown", which triggers `ShipAvailability#ensure_player_location_from_ship` to merge name keys in beside the coordinates on the next use. Coordinates are preserved but never read.

### 3.3 `user_ships` (`db/schema.rb:670-690`) — the ship record

`user_id` (not null), `ship_id` (not null), `total_scu`, `used_scu`, `shard_name`, **`location_name`** string, `status` (default `"docked"`, not null), `ship_slug`, `guid` (unique index), `shard_id`, `shard_user_id`, timestamps.

* `belongs_to :location, primary_key: :name, foreign_key: :location_name, optional: true` — the ship's location is a **name string**, not an id. Renaming a `Location` silently orphans every ship there (`Location has_many :user_ships ... dependent: :nullify` only fires on destroy).
* `status` is a free-text string. Observed values across the codebase: `docked`, `in_transit`, `interdicted`, `in orbit`, `landed`, `floating`, `aimlessly floating in space`. Mixed snake_case and prose; the admin badge helper only colours three of them.
* `shard_user` is optional. `infer_shard_user` fills it only when both `user_id` and `shard_id` are present; `shard_user_consistency` validates agreement when it is set.
* **There are no coordinate columns on `user_ships`.** The ship has a named location only.

### 3.4 `ship_travels` (`db/schema.rb:445-470`) — the journey record

`user_ship_id`, `from_location_id`, `to_location_id` (all not null, FKs to `locations`), `departure_tick` (not null), `arrival_tick` (not null), `total_duration_ticks` (default 0, not null), `is_paused` (default false, not null), `paused_at_tick`, `remaining_ticks_from_arrival`, `interdict_window_percent` (default 15, not null), `interdiction_count` (default 0, not null), `last_interdicted_tick`, `ship_travel_type` (string; `"gate_travel"` or null), `travel_guid` (not null, unique index), `completed_at_tick`, `rabbitmq_environment` (default `"prod"`, not null), timestamps.

* **Every time field is an integer simulation tick.** The only absolute times are `created_at`/`updated_at`.
* `completed_at_tick` is **dead**: `cleanup_after_arrival!` → `destroy_for_lifecycle!` → `destroy!`, so an arrived travel is deleted rather than marked. `scope :completed` can never match a row. There is no journey history (F-14).
* `arrival_tick = 0` is the interdiction sentinel, written by `interdict!` (`ship_travel.rb:138`). Three readers correctly exclude it: `ShipArrivalJob`, `ShipAvailability#process_due_arrival!`, `Api::ShipTravelController#process_due_arrival_for`, plus `due_for_arrival?` and `scope :stale_after_arrival`. **This behaviour must be preserved.**
* There is **no database constraint limiting a ship to one active travel.** The guards are application-level only.

### 3.5 `shards`, `ships`, `locations`, `ticks`, `tick_controls`

* `shards`: `name` (not null, **unique**), `region` (not null), `channel_uuid` (**no index, no uniqueness constraint**). `channel_uuid` is the external shard identity the client sends.
* `locations`: `name` not null with a unique index; `classification`, `parent_name`, `star_system_name`, `nickname`, `code`, `api_id`, `mass`/`periapsis`/`apoapsis`, many booleans, and `date_added`/`date_modified` as **integer epoch seconds** from the upstream importer.
* `ticks`: `sequence`, `current_tick`, `processed_at`. A de-facto singleton with **no singleton key and no uniqueness constraint** (contrast `tick_controls.singleton_key` unique). `Tick.instance` uses `first_or_create`, which writes a row on read when the table is empty.
* `tick_controls`: `running`, `singleton_key` unique, `last_tick_started_at`, `last_tick_completed_at`, `last_tick_failed_at`, `last_tick_error`, `last_tick_error_class`, `last_tick_job_id`, `last_heartbeat_at`, `failure_count`, `last_recovered_at`. **This is the richest timestamp surface in the application and it is not exposed anywhere in the admin UI.**

### 3.6 Field ownership as the code actually behaves today

| Field | Writers | Intended owner | Actual owner today |
|---|---|---|---|
| `shard_users.last_location` | 7 call sites (§1.2) | ambiguous | **last writer wins** |
| `user_ships.location_name` | `TravelService:55`, `GateTravelService:137`, `TradeService:208`/`254`/`366`, `ShipsController#deliver_ship:88`, `ShipTravelArrivalProcessor:16`, `ShipTravelController:633` | travel subsystem | **last writer wins** |
| `user_ships.status` | travel services, arrival processor, interdict/resume, `Tick#correct_ship_statuses` | travel subsystem | travel subsystem (consistent) |
| `user_ships.user_id` / `shard_id` / `shard_user_id` | `assign_authoritative_status_user_ship!` (overwrites), `StarTraderShipSync` (validates and refuses) | — | **two endpoints with opposite policies** (F-06) |
| `shard_users.wallet_balance` | `update_status_wallet_balance!`, trade paths, admin form | client via status | client, plus a 15 000-credit auto-grant (F-12) |
| `users.username` | `find_or_create_status_user!`, `StarTraderShipSync`, admin form | client via status | client, and a collision aborts the whole request (F-05) |
| `shards` rows | `find_or_create_status_shard!` creates; all other paths refuse | admin | **status creates them** (F-04) |
| `ship_travels.*` ticks | `TravelService`, `GateTravelService`, `interdict!`, `resume!` | travel subsystem | travel subsystem (consistent) |

---

## 4. Status synchronization investigation

### 4.1 The request lifecycle, as the code runs it

```
POST /api/status
 └─ Api::BaseController#parse_json_request            → @json_payload (400 on malformed JSON)
 └─ SecretGuidAuth#authenticate_secret_guid!          → 401 unless X-Secret-Guid | secret_guid | trade[secret_guid] == Setting.get('secret_guid')
 └─ TradesController#status
     ├─ normalized_status_payload                     → flattens @json_payload, @json_payload[:trade], params[:trade], params (first non-blank wins)
     ├─ Rails.logger.info "[status] payload keys: ..." (presence flags only)
     └─ TradeService.status(...)
         ├─ has_new_payload = ship_guid|ship_model|shard_uuid|player_guid|player_name present?
         ├─ NEW PATH  → status_by_ship_guid
         │   ├─ require ship_guid, ship_model, shard_uuid, player_guid, player_name  (400 ValidationError)
         │   ├─ validate_wallet_balance!                                             (400 if non-numeric)
         │   ├─ resolve_status_location!  → LocationResolver.resolve(location)
         │   │     location blank  → nil (no location write this request)
         │   │     unresolvable    → 400 "Location not found: X"   ← REQUEST ENDS, NOTHING WRITTEN
         │   ├─ authoritative_status_sync!
         │   │   ├─ find_or_create_status_shard!   Shard.find_by(channel_uuid:) || Shard.create!   ← F-04
         │   │   ├─ find_or_create_status_user!    User.find_by(twitch_id:) || find_by(uid:) || create!
         │   │   │                                 then user.update!(username: player_name)        ← F-05 (422 before the transaction)
         │   │   ├─ user.shard_users.find_or_create_by!(shard_id:)
         │   │   ├─ find_or_create_status_ship!    Ship.where("LOWER(model)=?") || Ship.create!
         │   │   ├─ UserShip.find_or_initialize_by(guid: ship_guid)
         │   │   └─ TRANSACTION
         │   │        shard_user.shard_name = shard.name
         │   │        shard_user.wallet_balance = wallet_balance if present
         │   │        shard_user.save! if changed?
         │   │        shard_user.update_current_location!(resolved_location) if resolved_location   ← the last_location write
         │   │        assign_authoritative_status_user_ship!  (user/shard/shard_user/ship/slug/scu/status,
         │   │                                                 and location_name = location.name if location)
         │   │      END TRANSACTION           rescue RecordNotUnique → retry (unbounded, F-17)
         │   └─ status_response_for
         │       ├─ update_status_wallet_balance!   (+ 15 000 auto-grant if balance == 0, F-12)
         │       ├─ Tick.current; active_status_travel; status_availability_for
         │       ├─ user_ship.reload; user_ship.touch     ← the only "last synced" trace that exists
         │       └─ build response (+ in-transit block when a travel is active)
         └─ LEGACY PATH → legacy_status (username + shard)
             ├─ resolve_status_location!   (same 400)
             ├─ Shard.find_by(channel_uuid: shard)  → 404 "Shard not found" if absent   ← opposite of the new path
             ├─ find_or_create_user(username, shard)   (downcases the username on create)
             ├─ shard_user = user.shard_users.find_by(shard_id:)  → 404 if absent
             ├─ user_ship  = shard_user.user_ships.order(updated_at: :desc).first
             └─ update_status_location!   (its own transaction: shard_user + user_ship)
```

### 4.2 Fields the endpoint receives, reads, validates and writes

| Incoming key | Accepted at | Required (new path) | Validation | Persisted to |
|---|---|---|---|---|
| `secret_guid` | header `X-Secret-Guid`, top level, `trade[]`, JSON body | yes | constant-time SHA-256 compare | — |
| `ship_guid` | any source | **yes** | presence only | `user_ships.guid` (lookup key; row created if absent) |
| `ship_model` | any source | **yes** | presence; `LOWER(model)` match, else **a new `Ship` row is created** | `user_ships.ship_id`, `ship_slug` |
| `shard_uuid` | any source | **yes** | presence; exact `channel_uuid`, else **a new `Shard` row is created** | `shard_users.shard_id`, `shard_name`, `user_ships.shard_id`/`shard_name` |
| `player_guid` | any source | **yes** | presence; matched against `users.twitch_id` then `users.uid` | `users.twitch_id`, and `users.uid` when safe |
| `player_name` | any source; falls back to `username` when any new-path key is present | **yes** | presence; then `user.update!(username:)` → unique `lower(username)` | `users.username` |
| `location` | any source | no | `LocationResolver.resolve`; unresolvable → **400** | `shard_users.last_location` (merged payload), `user_ships.location_name` |
| `wallet_balance` | any source | no | numeric string or `Numeric`, else 400 | `shard_users.wallet_balance` (and the 15 000 grant) |
| `username` | any source | legacy only | presence (legacy) | legacy path only |
| `shard` | any source | legacy only | presence (legacy), exact `channel_uuid`, else 404 | legacy path only |

Fields the endpoint **never** reads: any coordinate (`x`/`y`/`z`), star system, ship status, cargo, travel state, client timestamp.

### 4.3 Was synchronization removed, bypassed, or broken by refactoring?

**None of those.** `git log -S "update_current_location" -- app` returns exactly three commits — `09862f0` "potential fix for teleportation" (3 July 2026, which introduced the method), `c68145f` "added location support for status", and `c70f5ac` "update to status". Nothing has removed a status write since. `git log -S "last_location" -- app` returns only `392f0c2` (initial commit) and `09862f0`.

The only post-July change to the storage layer is `61331ac` (24 October 2026, "Repair full regression suite while preserving orbital and travel calibration"), which replaced `store :last_location, coder: JSON` with `coder: JsonStoreCoder`. §6.3 shows by direct probe that this **did not change the value written to the database** — both coders produce the same double-encoded JSON string. It only made reads tolerate rows that already held native jsonb objects. The commit is a read-path fix, not the regression.

So the synchronization code is intact. What changed is not the code; it is the probability that a real request reaches the write. Four paths end a status request before any write:

**(a) Unresolvable location → HTTP 400, nothing written (F-18).** `resolve_status_location!` (`trade_service.rb:228-240`) raises `ValidationError` when `LocationResolver.resolve` returns nil, and the controller maps that to `:bad_request`. The resolver needs a `locations` row whose normalized `name`, `nickname` or `code` matches, or a ranked match scoring ≥ 80. A client reporting a place that is not modelled as a `Location` — a hangar, a landing pad, a sub-area, a newly released location — gets a hard 400 and **no part of the status request is applied**: not the wallet, not the username, not the ship association. The existing test `trades_controller_test.rb:628` ("status with unknown location returns error and preserves existing locations") asserts exactly this behaviour as intended. One bad location string therefore disables the whole synchronization for that client.

This is my single most likely explanation for "status appears to have stopped updating", because it is the only failure mode that is *silent from the server's point of view* (one `Rails.logger.warn` at `trade_service.rb:234`) while being total from the client's.

**(b) Username collision → HTTP 422, nothing written (F-05).** `find_or_create_status_user!` (`trade_service.rb:163-186`) resolves the user by `twitch_id`/`uid` — correctly, by stable identifier — and then unconditionally does `user.update!(username: normalized_player_name, twitch_id: ...)`. If any *other* row already owns that username case-insensitively, `User`'s `uniqueness: { case_sensitive: false }` validation (and the DB index `index_users_on_lower_username_unique`) rejects it and `update!` raises `ActiveRecord::RecordInvalid`, which the controller maps to 422. This happens **before** `ActiveRecord::Base.transaction` opens, so nothing is written.

This is confirmed by a committed test, `test/services/trade_service_test.rb:449` — "status rejects a conflicting name without reassigning the original player" — which asserts `assert_raises(ActiveRecord::RecordInvalid)` and `assert_includes error.record.errors[:username], "has already been taken"`. The test's intent is sound (it prevents hijacking another account's name). The operational consequence is not: the affected player's status never syncs again, and the only signal is a 422.

The collision is made more likely by the legacy path: `find_or_create_user` (`trade_service.rb:1091-1118`) creates users with `username: username.to_s.downcase.strip`, while the new path writes the exact case the client sends. A legacy-created `testpilot` and a new-path `TestPilot` with a different `twitch_id` collide permanently.

**(c) Shard identity drift → writes land on a record nobody reads (F-04).** `find_or_create_status_shard!` (`trade_service.rb:151-161`) does `Shard.find_by(channel_uuid: shard_uuid.to_s.strip)` and, failing that, `Shard.create!(name: "Shard #{uuid}", region: "unknown", channel_uuid: uuid)`. Two consequences:

* The `channel_uuid` match is **exact and case-sensitive**, and `shards.channel_uuid` has no unique index. A client that sends the same shard GUID in different case — or a different GUID for the same live shard — gets a brand-new `Shard`, a brand-new `ShardUser`, and a fresh `last_location`/`wallet_balance`. The old `ShardUser` stops changing. From the operator's chair this looks exactly like "status stopped updating": the record they are watching is frozen while a sibling record is updating fine. `Shard`'s `validates :name, uniqueness: true` does not prevent it, because `"Shard ABC"` and `"Shard abc"` are different strings.
* The same input is treated three different ways across the API: `/api/status` creates (`find_or_create_status_shard!`), `/api/travel` raises 404 (`StarTraderShipSync#resolve_shard!`), and buy/sell accept either a `channel_uuid` *or* a case-insensitive shard **name** (`find_trade_shard`, `trade_service.rb:1304`). The brief asks whether case-sensitive shard-name issues have reappeared: the name-based lookups were removed from buy/sell in `61331ac` in favour of `shard_id`, which was the right fix, but `find_trade_shard` still accepts a name as an identifier and `find_or_create_status_shard!` still does an exact-case UUID match.

**(d) Payload-shape misrouting → HTTP 400 (F-19).** `normalized_status_payload` (`trades_controller.rb:241-265`) sets `new_status_payload` when *any one* of `ship_guid`, `ship_model`, `shard_uuid`, `player_guid`, `player_name` is present, and `TradeService.status` then requires **all five**. A legacy caller that sends `username` + `shard_uuid` (instead of `shard`) is routed to the new path and rejected with `400 "ship_guid is required"`. The legacy path is only reachable when none of the five new keys appears.

### 4.4 Do requests return HTTP 200 while silently failing to persist?

Mostly **no** — the hard failures above are loud (400/422/404). But there are three real silent-success cases:

1. **`location` absent.** `resolve_status_location!` returns `nil` for a blank location and the transaction simply skips `update_current_location!`. The response is 200 and reports the *existing* `player_location`. This is the correct answer to the brief's question "do missing or blank client location values accidentally overwrite valid existing information?" — **they do not.** `resolve_status_location!` short-circuits on `location_name.blank?`, and `assign_authoritative_status_user_ship!` guards its ship write with `if location`. The committed test `trades_controller_test.rb:618` ("status without location preserves existing location fields") asserts this. Blank is safe.
2. **Shard/ship/user silently created.** HTTP 200, everything persisted — just on new rows (F-04).
3. **UserShip silently re-parented.** `assign_authoritative_status_user_ship!` (`trade_service.rb:196-210`) assigns `user:`, `shard:`, `shard_user:` with no ownership check, so presenting someone else's `ship_guid` with your own `player_guid` transfers the row to you, and the response is 200. Four committed tests codify this: `trades_controller_test.rb:850` "status overwrites existing ship for different player", `:873` "...for different shard", `trade_service_test.rb:499`, `:509`. Meanwhile `StarTraderShipSync#validate_user_ship_ownership!` raises `"Ship does not belong to this player"` for the identical situation on `/api/travel`. This is the brief's "identity resolution cannot update another user's records" requirement, and today it can (F-06).

### 4.5 Transaction boundaries, callbacks, dirty tracking, parameter filtering

* **New path** — one `ActiveRecord::Base.transaction` (`trade_service.rb:105-120`) covering the `ShardUser` save, the location write, and the `UserShip` save. User/shard/ship creation happen **outside** it, so a later failure leaves an orphan `Shard`/`Ship`/`User` behind. `status_response_for` (including the wallet write and the 15 000 grant) also runs outside it.
* **Legacy path** — a separate transaction inside `update_status_location!` (`trade_service.rb:252-255`) covering only the two location writes.
* **No `update_columns` anywhere in the status path**, so callbacks and validations run on every write. `ShardUser` has `before_validation :sync_shard_name_from_shard`, `before_save :initialize_serialized_fields`, `validates :user_id, uniqueness: { scope: :shard_id }` (a SELECT per save), and `currency_not_nil`/`inventory_not_nil`. `UserShip` has `before_validation :infer_shard_user` and `validate :shard_user_consistency`.
* **Dirty tracking**: `shard_user.save! if shard_user.changed?` is a correct no-op guard. `update_current_location!` always calls `update!` with a freshly built hash; §6.3 shows `changed_in_place?` returns `true` whenever the stored raw value is a *native* jsonb object, so such rows are rewritten into the double-encoded string form on any save.
* **Parameter filtering**: `status` does **not** use strong parameters. `normalized_status_payload` reads raw values out of up to four sources via `first_present_param`. The unused `trade_params` method at `trades_controller.rb:297` permits a different, stale set of keys. Precedence is `@json_payload` → `@json_payload[:trade]` → `params[:trade]` → `params`, first non-blank wins — so a top-level key beats a nested one, and a *blank* value falls through to the next source rather than being treated as an explicit clear. That last point matters: a client cannot explicitly clear a field.

### 4.6 The travel constraint

The brief requires that `/api/status` must not initiate travel, validate a journey, or reject a normal request because a ship is in transit. **This requirement is met today, and there is a committed regression test for it.**

* `TradeService.status` never calls `TravelService`, `GateTravelService`, or `ShipAvailability#validate_usable!`. It uses `status_availability_for` (`trade_service.rb:456-479`), a *reporting* variant that returns a reason string instead of raising.
* `active_status_travel` (`trade_service.rb:481-487`) selects `completed_at_tick: nil AND (is_paused = true OR arrival_tick > current_tick)`, so it **includes interdicted travel** (`is_paused: true, arrival_tick: 0`) and reports it correctly through `status_travel_payload`, which uses `remaining_ticks_from_arrival` when paused. The `arrival_tick = 0` sentinel is handled correctly here.
* `test/controllers/api/trades_controller_test.rb:562` ("status with active travel returns clean in transit payload") asserts `assert_response :success`, `refute_includes response.body, "Ship is already in transit."`, `assert_no_difference("ShipTravel.count")`, and — importantly — `assert_equal travel_attributes, travel.reload.attributes`, i.e. the travel row is untouched. `test/services/trade_service_test.rb:230` ("status reports active travel without raising transit validation") covers the service level.
* `/api/travel` retains its duplicate-travel guards: `travel_in_progress?` (`ship_travel_controller.rb:700`), the explicit `ShipTravel.where(...).exists?` check at line 96, and `ShipAvailability#in_transit?` inside `TravelService#call`. Those are unaffected.

**But the location *write* has no in-transit guard (F-03).** `shard_user.update_current_location!(resolved_location) if resolved_location` and `user_ship.location_name = location.name if location` both execute regardless of travel state. A status call during flight can:

* move the ship's recorded `location_name` away from the journey's origin while `ship_travels` still says it is in transit (`Tick#correct_ship_statuses` will not notice — it only checks whether a travel row exists);
* re-point `shard_user.last_location`, which **permanently disarms** `ShipTravelArrivalProcessor#update_player_location_if_travel_origin_matches!`, because that guard tests `current_location.id == travel.from_location_id`;
* make the *next* `/api/travel` request fail with `"from_location does not match the player's current location."` (`ship_travel_controller.rb:655`).

The in-transit test above does not catch this because it passes `location: @location.name`, which **is** the travel's `from_location` — so the write is a no-op. The conflicting case is untested. This is the mechanism that connects objective 1 to objective 4.

### 4.7 Are updates targeting the correct user, shard membership and ship?

* **User** — correct and stable. Resolution is `twitch_id` then `uid`, never username (`trade_service.rb:166`). The brief's preference for stable identifiers over ambiguous username matching is satisfied *for lookup*. Username is only **written**, and that write is what aborts the request on collision (F-05). Note that `Api::ShipTravelController#resolve_cancel_user` and `find_or_create_user_by_guid_or_name` still match on `LOWER(username)`, with an explicit "Multiple users match player_name" rejection — a reasonable fallback, but a second resolution strategy in the same API.
* **Shard membership** — correctly scoped by `shard_id` after `61331ac`: `user.shard_users.find_or_create_by!(shard_id: shard.id)`, protected by the unique index on `(user_id, shard_id)`. The weakness is upstream, in which `Shard` gets resolved (F-04).
* **Ship** — targeted by `guid` (unique index), which is right, and the committed test `trades_controller_test.rb:639` ("status location updates only ship matching ship_guid") proves sibling ships are untouched. The weakness is that the row is *re-parented* rather than validated (F-06).

---

## 5. Admin user interface assessment

### 5.1 What exists

`Admin::UsersController#show` → `app/views/admin/users/show.html.erb` (207 lines). Sections rendered: header + "Edit User" link; identity card (avatar, username, uid, role badge, `users.wallet_balance`); "Account Details" (provider, twitch id, first/last name, country, role, last login, created, updated); "Active Ship" (model, status badge, location-or-destination); two raw-JSON panels (`global_inventory`, `purchased_items`); and a "User Ships" list with per-ship fields and a cargo table.

### 5.2 Confirmed limitations

| # | Limitation | Evidence |
|---|---|---|
| 1 | **No shard membership anywhere.** `ShardUser` is never referenced in the view, and `set_user` does not preload `shard_users`. Karma, fame, murder count, per-shard inventory, stats and per-shard wallet are all invisible. | `admin/users/show.html.erb` (whole file); `admin/users_controller.rb:28` |
| 2 | **No player location anywhere.** `last_location` is never rendered. The "Location / Destination" row shows the **ship's** `location_name`, so the single most important divergence in this report — ship location vs player location — cannot be seen in the admin UI at all. | same |
| 3 | **Wrong wallet.** Shows `users.wallet_balance`, which gameplay never writes; the authoritative value is `shard_users.wallet_balance` (per shard). An admin reading this page sees a balance unrelated to the player's credits. | `show.html.erb:84` vs `trade_service.rb:538-542` |
| 4 | **Interdicted ships render as having no travel.** The view uses `active_ship.active_travel`, whose scope is `where(is_paused: false, completed_at_tick: nil).where('arrival_tick >= ?', Tick.current)` — which excludes `is_paused: true, arrival_tick: 0`. An interdicted ship shows status `in_transit` with "Unknown destination". | `show.html.erb:13-22`; `user_ship.rb:17-19` |
| 5 | **Preloads are discarded.** `set_user` preloads `user_ships → active_travel → to_location`, but the view calls `@user.active_ship`, and `User#active_ship` is an instance method that re-queries `user_ships.order(updated_at: :desc).first`, overriding the `has_one` of the same name. Two extra queries per page, and the preload is wasted. | `user.rb:12` and `user.rb:44-46`; `show.html.erb:12` |
| 6 | **External avatar call leaks `user.uid`.** The fallback avatar is `https://crafatar.com/avatars/#{user.uid}?size=128&overlay` — a Minecraft skin service. Every admin page view sends the player's external identifier to a third party, for an account identifier that is a Twitch id. | `show.html.erb:45`; identical code in `index.html.erb:34` |
| 7 | **Raw JSON dumps, no location semantics.** `global_inventory`/`purchased_items` are rendered as `JSON.pretty_generate`. Nothing distinguishes a missing value from a zero value; blanks render as `"-"` for both. | `show.html.erb:50-54`, `:106`, `:166` |
| 8 | **Timestamps are unlabelled.** `strftime("%b %d, %Y %H:%M")` with no zone suffix and no conversion. `config.time_zone` is commented out in `config/application.rb:27`, so these are UTC rendered as if local. | `show.html.erb:100-102`, `:161-162` |
| 9 | **Three competing design systems.** The admin layout is `bg-gray-100` with a `bg-blue-900` sidebar. `users/show` and `users/index` are *dark* (`bg-slate-950`/`cyan-300`, 2026-06-12 `74840b5`). `user_ships/edit` is *light modern* (`bg-white`/`slate-200`/`cyan-600`, 2026-06-30 `4021768`). Everything else, including `shard_users/index`, is legacy (`bg-white p-6 rounded shadow` + bordered tables). `users/show` is the only dark page in a light layout. | `layouts/admin.html.erb:16`; the three views |
| 10 | **No navigation to ShardUsers.** `admin/shared/_side_bar.html.erb` links UserShips, Shards, ShipTravels and StarBitizenRuns, but not ShardUsers. | `_side_bar.html.erb:18-22` |
| 11 | **No index pagination.** `Admin::UsersController#index` loads every `User` with four levels of preload and renders them all. | `admin/users_controller.rb:8-11` |
| 12 | **No authorization test.** `test/controllers/admin/access_test.rb` covers only the data importers. There is no test that a non-admin cannot reach `/admin/users/:id`. | `access_test.rb` (20 lines) |

### 5.3 Query-efficiency assessment for the replacement

A correct page needs, per user: `shard_users → shard`, `user_ships → {ship, shard, shard_user, user_ship_cargos → commodity, ship_travels → {from_location, to_location}}`, plus `Location` rows for every `last_location` name and every `location_name`.

Three specific N+1 traps must be designed around:

1. **`ShardUser#current_location` is a per-call `Location.find_by(name:)`.** With *S* shards and *P* ships the naive page issues `S + P` location queries. Resolve all names in one `Location.where(name: [...]).index_by(&:name)` lookup in the controller and pass the map to the view.
2. **`UserShip#active_travel` and `#ship_travel` are scoped `has_one`s whose scope calls `Tick.current`.** `Tick.current` is `Tick.instance.current_tick` → a `ticks` query, and it also calls `first_or_create`. Read the tick **once** per request into a local and preload `ship_travels` whole, filtering in Ruby — do not call `active_travel` in a loop.
3. **`Tick.seconds_per_tick` is `Setting.get("seconds_per_tick")`, an uncached `settings` query per call.** Read it once per request.

### 5.4 Recommended replacement: information architecture

Design decisions, all defensible from repository evidence:

* **Adopt the light-modern token set from `app/views/admin/user_ships/edit.html.erb`** (`panel_class = "rounded-lg border border-slate-200 bg-white shadow-sm"`, `label_class = "text-xs font-semibold text-slate-500"`, `value_class = "mt-1 text-sm font-medium text-slate-900"`, `muted_value_class = "mt-1 text-sm text-slate-400"`, `table_head_class`, `table_cell_class`, `button_class`, `primary_button_class`, and the `display`/`timestamp`/`status_badge_class`/`render_field` lambdas). Rationale: it is the newest admin detail page (2026-06-30 vs 2026-06-12), it is the only one with a complete sectioned entity layout, and it is the only one that matches the `bg-gray-100` layout. Aligning `admin/users/index` to the same tokens is a nice-to-have, listed as optional in M6.
* **Progressive disclosure, not tabs.** Tabs hide the ship/player divergence behind a click, which is the one thing this page exists to show. Use stacked `<section>` panels in a 2:1 grid (details left, summary rail right), with `<details>` collapse only for per-ship cargo tables and per-shard raw JSON.
* **Status ribbon at the top.** One row of chips answering the operator's first question: current tick, the user's shard count, ship count, how many ships are in transit, how many ships are interdicted, and — the key one — **how many `(shard_user, user_ship)` pairs disagree about location**. Red when non-zero.

**A. User identity** (one panel, left column, top)
`User ID`, `Username`, `Twitch ID`, `UID`, `Provider`, `Role` (from `user_type`), `Account created` (`created_at`), `Record updated` (`updated_at`), `Last login` (`users.last_login`, labelled *"OAuth sign-in only — not gameplay activity"*), `Linked shards` (count + chips linking to each `ShardUser`), `Platform wallet` (`users.wallet_balance`, labelled *"legacy platform field — gameplay credits are per shard, see Shard memberships"*). Replace the crafatar fallback with a local initials avatar; never send `uid` off-site.

> `Last activity` is **not** available as a field. Use `MAX(shard_users.updated_at, user_ships.updated_at)` across the user's records and label it *"Last record write (approximate)"*. Do not label it "last seen".

**B. Shard memberships** (one panel per `ShardUser`, left column, repeating)
Header: shard name + `channel_uuid` in monospace + a link to `edit_admin_shard_user_path`. Body grid: `ShardUser ID`, `Shard ID`, `Wallet balance` (this is the real one), `Karma`, `Fame`, `Murder count`, `Member since` (`created_at`), `Record updated` (`updated_at`, labelled *"approximate last sync — also bumped by trades"*), `Ships on this shard` (count). Then the **Location block** (C). Then `<details>` for `inventory`, `currency`, `stats` raw JSON.

**C. Location** — the centrepiece. Render five distinct rows, never collapsed into one:

| Row | Source | Fallback when absent |
|---|---|---|
| **Named celestial location** | `last_location["name"]` / `["location_name"]` | `Unknown — no location recorded` (amber) |
| **Star system** | `last_location["star_system_name"]` | `Unknown` |
| **Classification** | `last_location["classification"]` | `—` |
| **Resolves to a Location row?** | `Location.find_by(name: …).present?` | `Stale — "<name>" no longer exists in the location catalog` (red) |
| **Physical coordinates** | `last_location["x"]`, `["y"]`, `["z"]` | `Not tracked — StarTrader does not record player coordinates` (grey) |

Then a **Ship vs player** comparison row per ship on that shard: `player location` | `ship location` | agreement badge (`Aligned` green / `Diverged` red / `Player location unknown` amber / `Ship in transit from X to Y` blue). Divergence is what the operator came for; make it the loudest element on the page.

Explicit guidance on the brief's coordinate question: **do not present `last_location` as coordinates and do not invent them.** §6.4 and §7.4 establish from `git log` that no live StarTrader path has ever written coordinates — the `{x,y,z}` shape belongs to the dead Minecraft endpoint. Show the coordinate row only when the keys are actually present, label it as legacy, and never fabricate it from a location name.

Also render, per shard, a **raw `last_location` payload** `<details>` block showing `JSON.pretty_generate`. Given F-07 (double encoding), that panel is the only way an operator can see what is physically stored.

**D. Ships** (one panel per `UserShip`, left column, after shard memberships; group under their shard)
`Ship model` + `name_full`, `Ship slug`, `UserShip ID`, `Ship GUID` (monospace, copyable), `Shard` (+ a warning chip when `user_ship.shard_id != shard_user.shard_id`), `Status` (badge; extend the helper to cover `interdicted`, `in orbit`, `landed`, `floating`, `aimlessly floating in space`), `Current location` (`location_name` + a "not in catalog" warning when it does not resolve), `Cargo` (`used_scu / total_scu` with a capacity bar, reusing the `user_ships/edit` pattern), `Created`, `Updated` (labelled *"bumped by every status call"* — `status_response_for` calls `user_ship.touch`), plus a **Travel sub-block** when a travel row exists:

`Travel GUID`, `Type` (`gate_travel` or `standard`), `From` → `To`, `Departure tick`, `Arrival tick`, `Current tick`, `Remaining ticks`, `Estimated arrival` (wall clock, see §6.6, with an explicit *"estimate — depends on tick cadence"* caption), `Paused?`, `Paused at tick`, `Remaining ticks from arrival`, `Interdiction count`, `Last interdicted tick`, `Interdict window %`, `RabbitMQ environment`, `Created at`.

> When `is_paused` is true, show `arrival_tick` as **`0 (interdicted — sentinel, not a real arrival)`** and compute remaining from `remaining_ticks_from_arrival`. Do **not** render tick 0 as a countdown. Select travels with the `active_status_travel` predicate (`completed_at_tick IS NULL AND (is_paused OR arrival_tick > current_tick)`), **not** `UserShip#active_travel`, which drops interdicted journeys (limitation 4).
> Because arrivals destroy the travel row (F-14), a ship with no travel row has either never travelled or has arrived. Label that state *"No journey on record"*, not "idle".

**E. Administrative diagnostics** (right rail, collapsed by default)
Only fields the current schema actually supports:

| Diagnostic | Source | Honest caveat to print |
|---|---|---|
| Last ShardUser write | `shard_users.updated_at` | also bumped by wallet/karma writes |
| Last UserShip write | `user_ships.updated_at` | bumped by **every** status call (`user_ship.touch`) |
| Simulation tick | `Tick.current` | — |
| Seconds per tick | `Tick.seconds_per_tick` | from `settings` |
| Tick chain health | `TickControl.instance`: `running`, `last_tick_started_at`, `last_tick_completed_at`, `last_tick_failed_at`, `last_tick_error_class`, `last_heartbeat_at`, `failure_count`, `last_recovered_at`, `stale?` | the richest timestamps in the app, currently unexposed |
| Identity resolution | `users.twitch_id`, `users.uid`, whether they match, whether `lower(username)` is unique | explains F-05 at a glance |
| Shard resolution | each `shard.channel_uuid`; a warning when two shards' `channel_uuid` differ only by case | explains F-04 at a glance |
| Location integrity | per shard/ship: does the stored name resolve to a `Location`? | explains F-18 at a glance |
| Divergence summary | count of ship/player location mismatches | — |

**Not available without new instrumentation** — state this explicitly in the playbook rather than inventing it: *last successful status synchronization* (as distinct from any other write), *last location update*, *source of the recorded location* (client vs arrival vs repair), and *synchronization warnings*. Each needs a new column or an audit table; §13 M5 proposes `shard_users.location_updated_at` + `location_source` as the minimal additive instrumentation.

### 5.5 Authorization and data exposure for the replacement

* Keep `Admin::ApplicationController`'s `authenticate_user!` + `require_admin`. Add the missing authz regression tests (§12).
* Do not render `Setting.get('secret_guid')`, the Bearer token, or any credential.
* Drop the crafatar fallback (limitation 6).
* Treat `uid`/`twitch_id` as sensitive-ish: render them, since identity debugging is the point of the page, but do not put them in URLs or query strings.
* Separately: `GET /users` currently renders every `User` row as JSON with no authentication (F-11). That is out of scope for a view rebuild but should not survive the same milestone series.

---
## 6. Timestamp and timezone audit

### 6.1 Baseline configuration (confirmed)

`config/application.rb:27` has `config.time_zone` **commented out**, so `Time.zone` is `UTC` and `ActiveRecord.default_timezone` is `:utc`. Every `datetime` column is stored and read in UTC, and `Time.current` is UTC. There is therefore **no timezone-conversion bug in persistence**. The exposure is in *presentation* (unlabelled UTC `strftime`) and in *absence* (no absolute time in the travel contract at all).

### 6.2 Inventory

Legend for **Kind**: `instant` = absolute point in time · `tick` = integer simulation counter · `duration` = elapsed seconds · `sim-seconds` = orbital simulation seconds · `epoch` = Unix epoch seconds integer.

#### Persistent datetime columns (all `timestamp without time zone`, UTC)

| Field | Owner | Kind | Producers | Consumers | Ambiguity | Recommendation |
|---|---|---|---|---|---|---|
| `users.created_at` / `updated_at` | `User` | instant | AR | admin views | unlabelled UTC in views | keep column; expose as `*_at_unix` only if an API needs it |
| `users.last_login` | `User` | instant | `SessionsController` | admin views | labelled "Last activity" by implication | keep; relabel in UI (§5.4 A) |
| `shard_users.created_at` / `updated_at` | `ShardUser` | instant | AR | admin (proposed) | `updated_at` conflates wallet/karma/location writes | keep; add `location_updated_at` (M5) |
| `user_ships.created_at` / `updated_at` | `UserShip` | instant | AR + explicit `user_ship.touch` in `status_response_for` | admin, `active_ship` ordering | `updated_at` is load-bearing for `order(updated_at: :desc)` ship selection **and** is bumped by every status call | keep; do not change the touch without checking `active_ship`, `latest_relevant_ship_travel`, and `ships_availability_json` ordering |
| `ship_travels.created_at` / `updated_at` | `ShipTravel` | instant | AR | `order(updated_at: :desc)` in `active_status_travel`, `latest_relevant_ship_travel`, `ship_travel` has-one | `created_at` is the only record of real departure wall-clock | keep; this is the anchor for the derived absolute arrival in §6.6 |
| `tick_controls.last_tick_started_at` / `last_tick_completed_at` / `last_tick_failed_at` / `last_heartbeat_at` / `last_recovered_at` | `TickControl` | instant | `update_columns(… Time.current)` | `stale?`, watchdog, logs | none; correct UTC | keep; **expose in the admin diagnostics panel** |
| `ticks.processed_at` | `Tick` | instant | `Tick#process_tick` | nothing reads it | none | keep; surface in diagnostics |
| `price_histories.recorded_at` | `City` | instant | `City` | charts | none | keep |
| `contact_messages.read_at`, `events.start_time`/`end_time`, `media.*` | misc | instant | admin/CMS | views | `events` rendered with `%I:%M %p` and no zone | keep; label zone |
| `delayed_jobs.run_at` / `locked_at` / `failed_at` | Delayed::Job | instant | gem | `TickJob.future_count`, `ready_count` | none | do not touch |

#### Simulation ticks — integers, **not** timestamps

| Field | Owner | Kind | Producers | Consumers | Recommendation |
|---|---|---|---|---|---|
| `ticks.current_tick` | `Tick` | tick | `Tick.increment!` | everything | **unchanged** |
| `ticks.sequence` | `Tick` | tick | `Tick.increment!` | `/api/set_tick`, `/api/increment_tick` responses | unchanged |
| `ship_travels.departure_tick` | `ShipTravel` | tick | `TravelService`, `GateTravelService`, `resume!` | status, `/api/location`, admin, Rabbit event, interdiction windows | **unchanged** |
| `ship_travels.arrival_tick` | `ShipTravel` | tick | same | same | **unchanged, including the `0` interdiction sentinel** |
| `ship_travels.total_duration_ticks` | `ShipTravel` | tick count (duration in ticks) | same | `duration_ticks`, `window_ticks`, `progress_fraction` | unchanged |
| `ship_travels.paused_at_tick`, `last_interdicted_tick`, `remaining_ticks_from_arrival`, `completed_at_tick` | `ShipTravel` | tick / tick count | `interdict!`, `resume!` | status, admin | unchanged (`completed_at_tick` is dead, F-14) |
| `Orbital::Clock` `origin_tick`, `activation_tick` | catalog JSON | tick | catalog | `clock_metadata` | unchanged |

#### Durations in seconds

| Field | Owner | Producers | Consumers | Ambiguity | Recommendation |
|---|---|---|---|---|---|
| `Tick.seconds_per_tick` | `Setting("seconds_per_tick")`, default 15 | admin settings | `seconds_remaining`, `TickJob.schedule_next_if_running!`, tick broadcast | none; **seconds** | document the unit in the setting label |
| `ShipTravel#seconds_remaining(current_tick)` | `ship_travel.rb:78` | — | status `ship.time_remaining`, `/api/travel` response | returns **0** for an interdicted travel because `arrival_tick` is 0 (F-13) | keep the method; stop using it for paused travels |
| status `travel.time_remaining` | `status_travel_payload` | — | client | correct for paused travels | keep |
| status `ship.time_remaining` | `status_response_for:421` via `latest_relevant_ship_travel` | — | client | **contradicts** `travel.time_remaining` when paused | fix to use the same paused-aware calculation |
| `GateTravelService::TRAVEL_TIME_SECONDS = 120` | constant | — | `travel_time_seconds` in the response | nominal, **not** quantized: with `seconds_per_tick = 7`, `ceil(120/7) = 18` ticks = 126 s, while the response still advertises 120 | report both, or report the quantized value |
| `TravelTiming.metadata` → `seconds_per_tick`, `nominal_travel_seconds` | `lib/travel_timing.rb:15` | `/api/travel` | client | correct and explicitly named | keep as the naming model |
| `TickWatchdogJob::WATCHDOG_INTERVAL = 30.seconds`, `TickControl::STALE_HEARTBEAT_THRESHOLD = 30.seconds` | constants | — | watchdog | none | keep |
| `TradeService.loading_time_seconds_for_scu`, `BASE_LOADING_TICKS = 10`, `LOADING_TICKS_PER_SCU = 2` | `trade_service.rb:1401-1411` | — | trade responses | ticks vs seconds in adjacent methods | keep; name consistently |

#### Simulation (orbital) seconds — a third, distinct time axis

`Orbital::Clock#metadata` (`lib/orbital/clock.rb:46-56`) returns `simulation_seconds`, `simulated_seconds_per_tick`, `orbital_seconds`, `orbital_progression_multiplier`, `orbital_seconds_per_tick`, `orbital_activation_anchor`. `Tick.simulated_seconds_per_tick` = `Setting("hours_per_tick") * 3600` (default 3600). These are **in-world simulation seconds measured from a catalog epoch**, not Unix time and not wall-clock elapsed. They are broadcast on `TickChannel` and consumed by `star_system_controller.js` for orbital rendering. `Tick.hours_per_tick` is an alias that returns *seconds* — a documented misnomer (`tick.rb:21`). **Leave this axis entirely alone**; the orbital calibration documents own it.

#### Already-epoch fields (the existing precedent)

| Field | Kind | Producers | Consumers |
|---|---|---|---|
| `locations.date_added` / `date_modified` (integer) | epoch | `Admin::Data::*Importer` (`location_data['date_modified'].to_i`) | not read for time |
| `production_facilities.date_modified` (integer) | epoch | `FacilitiesPopulator:121` | `MarketQuery` `MAX(date_modified)` → `source_modified_at` → `Time.at(...)` in `_market_results.html.erb:16` |

This is important: **the repository already carries upstream Unix epoch seconds in integer columns and already renders them with `Time.at(...).utc`.** That is the precedent to follow for the new convention, and it is the only existing round-trip from epoch integer to display.

#### API-exposed absolute timestamps

| Endpoint | Field | Format | Notes |
|---|---|---|---|
| `GET /api/commodities` | `"updated-at"` | `facility.updated_at.iso8601(3)` (`api/commodities_controller.rb:45`) | **the only absolute timestamp any API returns** |
| `POST /api/status` | — | none | ticks + second durations only |
| `POST /api/travel` | — | none | ticks + `nominal_travel_seconds` |
| `POST /api/gate_travel` | — | none | `current_tick` is actually `travel.departure_tick`, which is mislabelled |
| `GET /api/location/:id` | — | none | ticks + `progress` fraction |
| RabbitMQ `ShipArrival` | — | none | `departure_tick|arrival_tick` only (`rabbitmq_sender.rb:38-39`) |
| `TickChannel` | — | none | `tick`, `seconds_per_tick`, orbital clock metadata |

#### JavaScript

`app/javascript/controllers/star_system_controller.js:29-34` reads `data.tick` as `Number(...)` and compares integers. `market_results_controller.js:65,85,88` uses `Date.now()` for debouncing only. **There is no millisecond/second confusion anywhere in the client code**, because no absolute time ever crosses the boundary. `app/javascript/channels/tick_channel.js` is an empty stub.

#### Views

All admin index/show pages use `strftime` with no zone suffix — UTC rendered as if local. Two exceptions: `app/views/admin/star_bitizen_runs/index.html.erb:32` hardcodes `.in_time_zone('Pacific Time (US & Canada)')` (the only local-time conversion in the app, and therefore the only place subject to DST), and `app/views/star_trader/_market_results.html.erb:15-16` does it correctly — `iso8601` in a `<time datetime>` attribute plus `.utc.strftime("… UTC")` for humans, and `Time.at(epoch).utc` for the upstream integer.

### 6.3 The one measurement I could take: the `last_location` coder (F-07)

With no database available I probed the ActiveRecord type stack directly (ActiveRecord 8.0.1, no connection), reproducing `store :last_location, coder: JsonStoreCoder` over a `jsonb` column:

```
raw jsonb type:              serialize({"name"=>"Area18","id"=>7}) → "{\"name\":\"Area18\",\"id\":7}"
Type::Serialized + JsonStoreCoder (current):
    serialize → DB value:    "\"{\\\"name\\\":\\\"Area18\\\",\\\"id\\\":7}\""      ← a JSON *string*, not an object
    deserialize(that)        → {"name"=>"Area18", "id"=>7}                          ← round-trips
    deserialize(native hash) → {"name"=>"Area18", "id"=>7}                          ← tolerated
    changed_in_place?(native-raw, equal value) → true                               ← rewrites on every save
Type::Serialized + Coders::JSON (pre-61331ac):
    serialize → DB value:    "\"{\\\"name\\\":\\\"Area18\\\",\\\"id\\\":7}\""       ← identical
    deserialize(native hash) → raises TypeError: no implicit conversion of Hash into String
JSON.load(nil) → nil ; JsonStoreCoder.load(nil) → nil                               ← nil-safe
```

Three conclusions, all confirmed:

1. **`shard_users.last_location` holds a double-encoded JSON string, not a jsonb object.** Any SQL that treats it as an object (`last_location->>'name'`, `@>`, a GIN index) returns NULL or matches nothing. Player location is therefore **unqueryable and unindexable in SQL** — every read must load the row into Ruby. This is why the backfill rake task iterates `find_each` and why no reporting query over player location exists.
2. **`61331ac` is not the regression.** Both coders write the identical database value; the commit only made reads tolerate rows already stored as native objects. The read fix was correct.
3. Rows stored as native jsonb objects are silently rewritten into string form on their next save, because `changed_in_place?` reports a change. The column holds a mix of both representations, which is exactly what the model's own comment says.

### 6.4 Does `last_location` mean coordinates or a named location?

**Named location. Confirmed by `git log`, not inference.**

`git log --oneline -S "last_location" -- app` returns exactly two commits:

* `392f0c2` (26 Feb 2025, initial commit) — `Api::ShardUsersController#set_shard_user` writing `{ x: params[:x].to_f, y: …, z: … }`.
* `09862f0` (3 Jul 2026, "potential fix for teleportation") — `ShardUser#update_current_location!` writing the named-location payload.

The coordinate writer is **dead code**. It calls `User.find_or_create_by(minecraft_uuid: uid)` and `u.email = …`, and neither column exists: `email` was dropped by `db/migrate/20250304020522_remove_email_from_users.rb`, and `minecraft_uuid` appears nowhere in `db/schema.rb`. Any call raises before reaching the location write. The surrounding Minecraft lineage is still visible throughout the repository — `app/themes/Avatar/views/shared/_header.html.erb:27` literally reads *"A Minecraft Mod"*, `SessionsController#fetch_minecraft_uuid` talks to `api.minecraftservices.com`, the admin avatar fallback is a Minecraft skin service, and `routes.rb:53-54` still routes `edit_minecraft_uuid`/`update_minecraft_uuid` to actions `UsersController` does not define.

So the brief's warning is exactly right and now has evidence behind it: **Minecraft-style coordinates and StarTrader's celestial locations are not the same concept, and StarTrader has never populated the coordinate form.** `current_location_name` reads only `name`/`location_name`. Nothing in the live application supplies, validates, or consumes `x`/`y`/`z`.

**Recommendation: keep `last_location` as the named-location payload, keep merging rather than replacing so legacy coordinate keys survive untouched, and do not add coordinate tracking.** StarTrader's authoritative spatial model is `Location` + the orbital catalog; the ship/player position that gameplay actually needs is a named `Location`. If physical coordinates are ever wanted, they belong in new, explicitly named columns with a stated frame of reference — not retrofitted into this field.

### 6.5 Proposed convention

| Category | Representation | Null | Rationale |
|---|---|---|---|
| **Absolute instants in API responses** | **integer Unix epoch seconds, UTC**, key suffix `_at_unix` | key present with JSON `null` | matches the brief; matches the existing `date_modified` precedent; integer avoids float drift and JS `Number` issues |
| **Persistent Rails timestamps** | **unchanged** `datetime` (timestamp without time zone, UTC) | SQL NULL | changing them buys nothing; `Time.zone` is already UTC; `updated_at` ordering is load-bearing in six places |
| **New instrumentation timestamps** | `datetime` columns, exposed as `_at_unix` when serialized | NULL | consistent with the above |
| **User-facing dates** | convert from UTC with an **explicit** zone and always print the zone abbreviation | `"Never"` / `"Not recorded"` | fixes the unlabelled-`strftime` problem; the one hardcoded Pacific conversion becomes a deliberate setting |
| **Durations** | integer **seconds**, key suffix `_seconds` | `null` | `nominal_travel_seconds` already does this |
| **Tick counts (durations in ticks)** | integer, key suffix `_ticks` | `null` | `total_duration_ticks`, `remaining_ticks` already do this |
| **Simulation ticks (points on the tick axis)** | integer, key suffix `_tick` | `null` | `departure_tick`, `arrival_tick`, `current_tick` — **unchanged, including `0`** |
| **Orbital simulation seconds** | unchanged, keys already explicit (`simulation_seconds`, `orbital_seconds`) | — | owned by the orbital documents |
| **Precision** | **integer seconds** for `_at_unix`; keep `iso8601(3)` where it already exists | — | nothing in the domain needs sub-second resolution; the fastest clock is a 15-second tick |

Naming rule, stated so an implementer needs no further judgement: **`_tick` is a point on the tick axis; `_ticks` is a count of ticks; `_seconds` is a count of seconds; `_at_unix` is a point on the Unix axis; `_at` is a Rails datetime.** No field may change axis without changing suffix.

### 6.6 Should an absolute arrival timestamp be exposed?

**Yes — additively, and labelled as an estimate.** `arrival_tick` keeps its exact current meaning.

```ruby
# derived, not stored; nil when paused or when arrival_tick is the 0 sentinel
def estimated_arrival_at(current_tick = Tick.current)
  return nil if is_paused? || arrival_tick.to_i <= 0
  remaining = [arrival_tick.to_i - current_tick.to_i, 0].max
  Time.current + (remaining * Tick.seconds_per_tick).seconds
end
```

Expose as `arrival_at_unix` (integer, or `null`) alongside the unchanged `arrival_tick`, `departure_tick`, `current_tick`, `remaining_ticks`, `time_remaining`.

Why it is worth having, and why it must be an estimate:

* **Client/server clock skew.** Today a client cannot render a countdown without trusting its own clock *and* polling for the tick. An absolute arrival instant lets it reconcile.
* **Tick-chain stalls are real and expected.** `TickJob` self-chains at `Tick.seconds_per_tick`, and `TickWatchdogJob` exists precisely because the chain breaks (`TickControl.failure_count`, `last_recovered_at`, `stale?`). Ticks are **not** a uniform wall clock. Any derived arrival instant moves forward whenever the chain stalls, so it must be recomputed per response and labelled an estimate. Do not persist it, and do not let any arrival logic read it — arrival remains `arrival_tick <= Tick.current`.
* **DST is irrelevant** to this calculation because everything is UTC and the arithmetic is on an elapsed-seconds offset.
* **Restart/recovery** is unaffected: tick state lives in `ticks` and `tick_controls`, both durable; a derived value needs no recovery.
* **Interdiction** returns `null` rather than a fabricated instant, because a paused journey genuinely has no scheduled arrival. This is the correct representation of `arrival_tick = 0` on the Unix axis and preserves the sentinel's meaning instead of leaking `1970-01-01`.

### 6.7 Compatibility assessment

| Change | Breaking? | Needs client update? | Needs migration? |
|---|---|---|---|
| Add `arrival_at_unix`, `departure_at_unix` to status/travel responses | no (additive) | no — only to *use* it | no |
| Fix `ship.time_remaining` / `ship.arrival_tick` for paused travels | **yes, behaviourally** — the value changes from `0` to the real remaining seconds | consumers that special-case `0` must be checked | no |
| Add `*_at_unix` to admin-only payloads | no | no | no |
| Label timezones in admin views | no | no | no |
| Make the Pacific conversion a setting | no | no | no |
| Add `shard_users.location_updated_at` + `location_source` | no | no | **yes** (additive, nullable) |
| Change any `_tick` field's type or meaning | **yes** | yes | yes |

**No API versioning and no dual-format window are required**, because every change above is additive except the paused-countdown fix. Recommended sequencing: ship the additive `_at_unix` fields and the admin labelling first; treat the `ship.time_remaining` correction as a separate, announced change, because the external StarBitizen bot consumes that key and I cannot see its code from this repository (§14 Q6).

---

## 7. Jump lifecycle investigation

### 7.1 What "Jump" is in this codebase

**Confirmed: the Jump is `POST /api/gate_travel` → `Api::GateTravelController#gate_travel` → `GateTravelService`.** There is no route, controller, service, or job named `jump`; `grep -ri jump app lib config` matches only the user-facing error strings `"You are not at a valid Jumpgate location."` and `"No valid destination Jumpgate found."` inside `GateTravelService`.

It is **not** instantaneous. It creates a real `ShipTravel` with `ship_travel_type: "gate_travel"`, a nominal 120-second duration (`TRAVEL_TIME_SECONDS`, quantized to `ceil(120 / seconds_per_tick)` ticks), and it arrives through the ordinary `ShipArrivalJob` → `ShipTravelArrivalProcessor` path. The committed test `test/controllers/api/gate_travel_controller_test.rb:331` ("ship arrives after the two minute gate travel delay using the normal arrival job") proves this.

Gateway naming convention, from `target_star_system_from` and the tests: a gateway in system **A** named **"B Gateway"** leads to system **B**, and the matching arrival gateway in **B** is named **"A Gateway"**. Parenthetical suffixes (`"Pyro Gateway (Stanton)"`) are stripped by `normalized_gateway_name` before the suffix test.

### 7.2 The twelve lifecycle steps — which actually exist

| # | Step | Exists? | Implementation |
|---|---|---|---|
| 1 | Client issues Jump | yes | `POST /api/gate_travel`, `gateway_name` under any of five alias keys |
| 2 | Request reaches server | yes | `Api::BaseController` JSON parse → `SecretGuidAuth` |
| 3 | User identity resolved | **no — not from the request** | the request carries **no `player_guid` and no `player_name`**. The user is derived from `user_ship.user` after looking the ship up by `guid`. Committed test `:271` "endpoint no longer requires or uses username" confirms this is deliberate. |
| 4 | Shard and ship identity resolved | partly | ship: `UserShip.find_by(guid:)`. Shard: `user_ship.shard || user_ship.shard_user&.shard || Shard.find_by(name: user_ship.shard_name)` — a three-way fallback, and `shard_uuid` is never supplied or checked |
| 5 | Eligibility checked | yes, but see §7.3 | `ShipAvailability#validate_usable!` (processes due arrivals, requires ship and player co-located, rejects in-transit **and** paused), then `validate_gateway_location!` |
| 6 | Origin and destination determined | yes | `resolved_origin_gateway` → `target_star_system_from` → `resolve_gateway!` scoped to the target system |
| 7 | Jump initiated | yes | `ShipTravel.create!(ship_travel_type: "gate_travel", …)` inside `ShipTravel.transaction` |
| 8 | **Ship location changes** | yes — **immediately, to the origin gateway** | `user_ship.update!(location_name: origin_location.name, status: "in_transit")` (`gate_travel_service.rb:137`) |
| 9 | **Player location changes** | **NO — never** | `grep` over `app/services/gate_travel_service.rb` finds no `update_current_location!` and no `shard_user` write of any kind |
| 10 | Related records persisted | partly | travel + ship in one transaction; `ShardUser` untouched |
| 11 | Client receives result | yes | includes `new_location` = the **arrival** gateway, even though arrival has not happened |
| 12 | Subsequent status is consistent | **no** | status reports ship at the origin gateway and player wherever they were, with `available_at_player_location: false` |

### 7.3 Confirmed defects in the Jump path

**(a) The player is never moved — at departure or at arrival (F-01).**

Compare the two travel services directly:

```ruby
# app/services/travel_service.rb:55-56   (normal travel)
user_ship.update!(location_name: @from_location.name, status: "in_transit")
user_ship.shard_user&.update_current_location!(@from_location)      # ← player follows

# app/services/gate_travel_service.rb:137  (the Jump)
user_ship.update!(location_name: origin_location.name, status: "in_transit")
#                                                                   ← nothing
```

At arrival, `ShipTravelArrivalProcessor` moves the ship unconditionally but the player only conditionally:

```ruby
# app/services/ship_travel_arrival_processor.rb:43-51
def update_player_location_if_travel_origin_matches!
  shard_user = travel.user_ship.shard_user
  return unless shard_user
  current_location = shard_user.current_location
  if current_location.nil? || current_location.id == travel.from_location_id
    shard_user.update_current_location!(travel.to_location)
  end
end
```

Because the Jump never set the player to `travel.from_location`, the equality fails whenever the recorded player location differs from the resolved origin gateway — and then the player is **not** moved at arrival either. The player is left in the departure system while the ship sits in the destination system.

**(b) The Jump teleports the ship past its own eligibility check (F-02).**

The ordering in `GateTravelService#call` is:

```ruby
availability       = ShipAvailability.new(...).validate_usable!   # line 40 — validates the ship's REAL location
current_location   = availability.ship_location                    # line 41
origin_location    = resolved_origin_gateway(current_location)     # line 44 — may be a DIFFERENT location
validate_gateway_location!(origin_location)                        # line 45 — only checks the NAME ends in " Gateway"
...
user_ship.update!(location_name: origin_location.name, ...)        # line 137 — moves the ship there, instantly
```

`resolved_origin_gateway` returns `current_location` only when `gateway_name` is blank. When a `gateway_name` is supplied it returns `LocationResolver.find_in_star_system!(input_name: gateway_name, star_system_name: current_location.star_system_name)` — **any** gateway in the same star system. Nothing checks that the ship is at it. So a `gateway_name` turns the Jump into "teleport to that gateway, then jump", and the player is left behind.

**This is asserted by the repository's own test suite.** `test/controllers/api/gate_travel_controller_test.rb:179-194`:

```ruby
test "ship in Pyro can enter Nyx Gateway without parenthetical suffix" do
  @user_ship.update!(location_name: @pyro_location.name)        # ship at "Ruin Station"
  post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Nyx Gateway")
  assert_response :success
  assert_equal @nyx_gateway_in_pyro.name, @user_ship.reload.location_name   # ← asserts the teleport
  ...
end
```

In that test `@shard_user` is created with no `last_location`, so `ShipAvailability#ensure_player_location_from_ship` first copies the ship's location ("Ruin Station") onto the player; the service then moves the ship to "Nyx Gateway (Pyro)". The test asserts nothing about `@shard_user`. After it, player = Ruin Station, ship = Nyx Gateway (Pyro), `travel.from_location` = Nyx Gateway (Pyro). At arrival the guard compares Ruin Station to Nyx Gateway (Pyro), they differ, and the player is never updated. Three further tests (`:196`, `:206`, `:245`) exercise the same shape. The defect is not hypothetical; it is fixtured and asserted.

**(c) A status call during a jump makes the arrival guard permanently unfixable (F-03 × F-01).**
Even in the well-behaved case — ship and player both at the gateway, no `gateway_name` — one `/api/status` call carrying a `location` while the jump is in flight rewrites `last_location`, and from that moment the arrival guard can never match. This is the strongest argument for making the authority model explicit rather than patching either service in isolation.

**(d) The Jump always publishes arrivals to the production broker (F-22).** `create_gate_travel!` omits `rabbitmq_environment`, so `ShipTravel#normalize_rabbitmq_environment` applies `DEFAULT_ENVIRONMENT` (`"prod"`). `/api/travel` honours `?rabbitmq=dev` and `test/services/travel_service_test.rb` covers that for normal travel. A dev-environment jump therefore emits its `ShipArrival` into production.

**(e) `GateTravelService` raises `NoMethodError` when the ship has no `shard_user` (F-15).** Line 40 passes `user_ship.shard_user` (optional association) into `ShipAvailability`, whose `ensure_player_location_from_ship` calls `shard_user.current_location` with no nil guard (`ship_availability.rb:72-74`). The controller's bare `rescue => e` converts that into a 422 whose message is a Ruby `NoMethodError` string.

**(f) No duplicate-jump protection by `travel_guid`.** `GateTravelController` passes `travel_guid: travel_guid_param`, and `GateTravelService#initialize` substitutes `SecureRandom.uuid` when it is blank. A client that omits `travel_guid` and retries after a timeout gets a *new* guid each time, so the unique index on `ship_travels.travel_guid` provides no idempotency. The only guard is `raise StandardError, "Already in transit" if user_ship.active_travel.present?` plus the earlier `validate_usable!` — both application-level, both racy. `/api/travel` by contrast **requires** `travel_guid` (`ship_travel_controller.rb:21-23`), which makes a retry safely collide on the unique index.

### 7.4 Which components update which location fields

| Field | Written by | Not written by |
|---|---|---|
| `user_ships.location_name` | `TravelService:55`, `GateTravelService:137`, `ShipTravelArrivalProcessor:16`, `TradeService` status (`:208`, `:254`, `:366`), `ShipsController#deliver_ship:88`, `ShipTravelController#initialize_unknown_locations_from_request!:633`, admin form | — |
| `shard_users.last_location` | `TradeService` status (`:111`, `:253`), `TravelService:56`, `ShipTravelArrivalProcessor:49` (conditional), `ShipAvailability:74`, `ShipTravelController:634` | **`GateTravelService`**, `ShipsController#deliver_ship`, the admin UI |
| `ShardUser#current_location` | nothing — derived reader | — |
| coordinates | nothing live (dead `Api::ShardUsersController` only) | everything |

Direct answer to the brief's explicit question — *"does a successful Jump change a named celestial location without updating the player's coordinate-based `last_location`?"* — **the Jump does not update `last_location` at all, and `last_location` is not coordinate-based in StarTrader.** It changes the ship's named location only. No legitimate client or server data supplies coordinates (§6.4), so the correct repair is to update the *named* payload through `update_current_location!`, never to synthesize coordinates and never to overwrite the JSON structure with a bare name string.

### 7.5 Expected state per lifecycle case

Recommended target behaviour. "Player" = `shard_users.last_location`; "Ship" = `user_ships.location_name`.

| Case | Ship | Player | Travel row | Current behaviour |
|---|---|---|---|---|
| Jump accepted, ship already at the gateway | origin gateway | **origin gateway** | created, `in_transit` | ship ✓, **player not written** |
| Jump accepted with a `gateway_name` for a gateway the ship is not at | **should be rejected** | unchanged | none | ship **teleported**, player stranded |
| Jump rejected (not at a gateway / no destination / already in transit) | unchanged | unchanged | none | ✓ correct |
| Duplicate Jump, same `travel_guid` | unchanged | unchanged | none; return the existing travel | ✓ by `active_travel` check, but **not idempotent** when `travel_guid` is omitted |
| Jump while travelling | unchanged | unchanged | none | ✓ `validate_usable!` rejects |
| Interdicted mid-jump | unchanged | unchanged | `is_paused: true`, `arrival_tick: 0` | ✓ correct; `status` reports it correctly |
| Resumed | unchanged | unchanged | fresh `departure_tick`/`arrival_tick` | ✓ correct |
| Arrival | destination gateway | **destination gateway** | destroyed | ship ✓; player **only if** the guard matches |
| Cancelled | unchanged, status → `"aimlessly floating in space"` | unchanged | destroyed | ✓; note the ship stays at the origin gateway it was teleported to |
| Timeout then retry | unchanged | unchanged | one travel | depends on `travel_guid` being supplied |
| Concurrent status + Jump | — | — | — | **status can overwrite both mid-flight** |
| Missing `shard_user` | — | — | — | `NoMethodError` → 422 |
| Destination resolution failure | unchanged | unchanged | none | ✓ clear error, but **only after** `validate_usable!` has possibly already written the player location via `ensure_player_location_from_ship` |

The last row is a real subtlety: `ShipAvailability#status` has a **write side effect** (`ensure_player_location_from_ship`) and `process_due_arrival!` has another, so a Jump that is subsequently rejected may still have mutated player location and processed an arrival. Any repair should keep those repairs idempotent and harmless, or move them out of the validation path.

### 7.6 When should the player's location actually change?

The distinction the brief asks for, stated as a rule:

* **Departure** — the player is boarding the ship, so the player's location should be set to the journey **origin** (what `TravelService:56` already does). This is a *normalization*, not a move: it makes the arrival guard's precondition true and so is the mechanism that makes arrival work at all.
* **In flight** — the player's recorded location should **not** change. The authoritative answer is "in transit from X to Y", which is derivable from the travel row. A client observation during flight should be recorded as an observation (and ignored, or logged), never applied.
* **Arrival** — the player's location should be set to the **destination**, unconditionally for the ship's own occupant, because the server initiated and completed the journey.
* **Cancellation / interdiction / resume** — no player location change. The journey's origin remains the last confirmed location.
* **Client `*status` while idle** — client-authoritative. The player may have walked, taken a tram, or been killed and respawned; the server has no better information.

---

## 8. Root-cause register

Severity: **Critical** = player-visible state corruption · **High** = feature does not work or data integrity at risk · **Medium** = wrong/missing information or latent integrity risk · **Low** = hygiene, dead code, or cosmetic.

### 8.1 Confirmed findings

| ID | Sev | Symptom | Evidence | Root cause | Conf. | Components | Proposed resolution |
|---|---|---|---|---|---|---|---|
| **F-01** | Critical | A successful Jump leaves the player's `last_location` at the pre-jump location, forever | `grep` over `app/services/gate_travel_service.rb` finds no `shard_user` write; contrast `travel_service.rb:56`. Arrival guard `ship_travel_arrival_processor.rb:43-51`. Asserted shape in `gate_travel_controller_test.rb:179-194` | `GateTravelService` is the only travel writer that does not normalize the player to the journey origin, so the arrival processor's equality guard never matches | Confirmed | `GateTravelService`, `ShipTravelArrivalProcessor`, `ShardUser` | In `create_gate_travel!`, inside the existing transaction, call `user_ship.shard_user&.update_current_location!(origin_location)` exactly as `TravelService` does. Then make the arrival guard authority-based rather than equality-based (see F-03). |
| **F-02** | High | A Jump with a `gateway_name` instantly relocates the ship to a gateway it is not at | `gate_travel_service.rb:40` validates the real location, `:44` resolves a possibly different origin, `:45` only checks the name suffix, `:137` writes it. Asserted by `gate_travel_controller_test.rb:179`, `:196`, `:206`, `:245` | Eligibility is validated against the ship's actual location, but the journey origin is resolved afterwards from client input with no co-location check | Confirmed | `GateTravelService`, `LocationResolver` | Reject when `origin_location.id != availability.ship_location.id` (`"You are not at <gateway>."`). Requires updating the four tests, which currently assert the teleport — an owner decision (§14 Q2). |
| **F-03** | High | `/api/status` overwrites ship and player location mid-flight, disarming arrival | `trade_service.rb:111` and `:208` are unguarded; the in-transit test `trades_controller_test.rb:562` only passes the travel's own `from_location`, so the conflicting case is untested | No authority model: client-reported location is applied unconditionally, including while the server holds an active or paused travel | Confirmed | `TradeService`, `ShipTravelArrivalProcessor`, `ShipAvailability` | While an active or paused travel exists, do not apply the client location to either record; log the divergence and return the authoritative travel state (status must still return 200 — §4.6). Then change the arrival guard from "equals origin" to "no newer client-authoritative observation", so arrival always lands the player. |
| **F-04** | High | A player's `ShardUser` "stops updating" while a sibling record updates fine | `trade_service.rb:151-161` creates on miss; `shards.channel_uuid` has no unique index (`schema.rb:437-443`); asserted by `trades_controller_test.rb:758` and `trade_service_test.rb:339`. `/api/travel` raises 404 for the same input (`star_trader_ship_sync.rb:67-71`) | Exact, case-sensitive `channel_uuid` match with silent create-on-miss, and three different shard-resolution policies across one API | Confirmed | `TradeService`, `StarTraderShipSync`, `Shard` | Normalize `channel_uuid` (strip + case-fold) on both read and write, add a unique index, and decide one policy for create-on-miss (§14 Q3). Audit for existing case-variant duplicates before changing anything. |
| **F-05** | High | Every status call for one player returns 422 and nothing ever syncs | `trade_service.rb:171` `user.update!(username: …)` unconditional; `user.rb:17` + index `index_users_on_lower_username_unique`; asserted by `trade_service_test.rb:449` | The username write is unconditional and runs **before** the transaction, so a case-insensitive collision with any other account aborts the whole request | Confirmed | `TradeService`, `User` | Keep refusing to steal the name, but stop failing the request: rescue the rename, keep the correct `twitch_id`-resolved user, apply location/wallet/ship as normal, and surface a `username_conflict` warning in the response and the admin diagnostics panel. |
| **F-06** | Medium | `/api/status` reassigns an existing `UserShip` to whichever player presents its guid | `trade_service.rb:196-210` assigns `user`/`shard`/`shard_user` unconditionally; asserted by `trades_controller_test.rb:850`, `:873`, `trade_service_test.rb:499`, `:509`; `StarTraderShipSync#validate_user_ship_ownership!` refuses the identical case | Two endpoints hold opposite ownership policies for the same rows, and `guid` alone is treated as proof of ownership | Confirmed | `TradeService`, `StarTraderShipSync`, `UserShip` | Pick one policy (§14 Q4). Recommended: keep the transfer (hull resale is plausible) but make it explicit and auditable — log an `event=user_ship_reparented` line with both user ids, show it in admin diagnostics, and never transfer while the ship has an active travel. |
| **F-07** | Medium | Player location cannot be queried, filtered, indexed, or reported in SQL | DB-free probe, §6.3: `store … coder: JsonStoreCoder` over `t.jsonb` writes a JSON *string*. Identical before `61331ac` | A `store` coder wraps the jsonb type rather than replacing it, so the payload is JSON-encoded twice | Confirmed | `ShardUser` | Low priority and **not** the reported regression. If addressed: drop the coder for `last_location`, keep a read-time normalizer for legacy string rows, backfill with a one-off task, then add a GIN index. Changing the write format without a backfill would strand `current_location_name` for string rows. |
| **F-08** | Medium | `last_location` carries two incompatible historical schemas; the coordinate one is unreachable | `git log -S "last_location" -- app` → only `392f0c2` and `09862f0`; `shard_users_controller.rb:34` uses `minecraft_uuid` and `u.email`, neither in `db/schema.rb` | Minecraft-era code was never removed when StarTrader took over the schema | Confirmed | `Api::ShardUsersController`, `ShardUser`, `UsersController` | Document the named-location payload as the sole contract. Delete the dead Minecraft endpoint, its route, and the two unimplemented `minecraft_uuid` routes in a hygiene milestone. Keep merging rather than replacing in `update_current_location!` so legacy keys survive. |
| **F-09** | Medium | Admin cannot see shard membership, player location, or the real wallet | `app/views/admin/users/show.html.erb` in full; `admin/users_controller.rb:28` has no `shard_users` preload | The page was built around `User` + `UserShip` before `ShardUser` carried the gameplay state | Confirmed | `Admin::UsersController`, the show view | Rebuild per §5.4. |
| **F-10** | Medium | `POST /api/increment_tick` advances the whole simulation with no authentication; `POST /api/set_tick` always 500s | `Api::TickController < ApplicationController` (no `SecretGuidAuth`) with `skip_before_action :verify_authenticity_token`; `grep -rn set_current app lib test config` matches only the caller | The controller was never migrated to `Api::BaseController`, and `Tick.set_current` was removed or never written | Confirmed | `Api::TickController`, `Tick` | Add `SecretGuidAuth` (or admin-only), and either implement `Tick.set_current` with the advisory lock or delete the action and its route. |
| **F-11** | Medium | `GET /users` returns every user row, including `uid` and `twitch_id`, unauthenticated | `routes.rb:52 resources :users`; `UsersController#index` → `render json: User.all`. `edit_minecraft_uuid`/`update_minecraft_uuid` routes have no actions | A scaffold `resources :users` was never narrowed | Confirmed | `UsersController`, `routes.rb` | Restrict the route set to what is used, require authentication, and drop the dead member routes. |
| **F-12** | Medium | A bankrupt player is silently refunded 15 000 credits on every status call | `trade_service.rb:541` `shard_user.update!(wallet_balance: 15000) if shard_user.wallet_balance == 0`; asserted by `trade_service_test.rb:298` | A starting-balance seed was implemented inside the per-request status read path | Confirmed | `TradeService` | Move it to `ShardUser` creation only (a `wallet_balance` default or an explicit grant when the record is new), so an earned zero balance stays zero. Owner-visible gameplay change — flag it. |
| **F-13** | Medium | One status response contains two contradictory countdowns for an interdicted ship | `status_response_for:418-421` uses `latest_relevant_ship_travel` + `seconds_remaining`, which yields `arrival_tick: 0` and `time_remaining: 0`, while `status_travel_payload:489-507` correctly uses `remaining_ticks_from_arrival` | The legacy `ship` block predates interdiction and reads `arrival_tick` arithmetically, ignoring the `0` sentinel | Confirmed | `TradeService` | Make the `ship` block paused-aware using the same calculation as `status_travel_payload`. Behavioural change for any consumer special-casing `0` — see §6.7. |
| **F-14** | Low | No journey history; `completed_at_tick` can never be set | `cleanup_after_arrival!` → `destroy_for_lifecycle!` → `destroy!`; `scope :completed` is unreachable | Arrival deletes the row instead of completing it | Confirmed | `ShipTravel`, `ShipTravelArrivalProcessor`, admin | Out of scope for the four objectives. If journey history is wanted later, set `completed_at_tick` and stop destroying — but that changes every "active travel" predicate, so it needs its own milestone. In the admin UI, label "no travel row" as *"No journey on record"*. |
| **F-15** | Low | A Jump by a ship with no `shard_user` fails with a raw `NoMethodError` message | `ship_availability.rb:72-74` calls `shard_user.current_location` with no nil guard; `gate_travel_service.rb:40` passes the optional association | Optional association dereferenced in a service that assumes it is present | Confirmed | `ShipAvailability`, `GateTravelService` | Guard with `return unless shard_user`, and return a clear `"Ship is not linked to a shard membership"` error. |
| **F-16** | Low | Every unresolved location name scans the whole `locations` table in Ruby | `location_resolver.rb:236-242` `each_location` → `Location.find_each`; reached from `resolve_status_location!` for any non-exact name | Ranked fuzzy matching implemented in Ruby with no candidate narrowing | Confirmed | `LocationResolver`, `TradeService` | Out of scope. Note it as a cost of the §4.3(a) repair: better location handling will increase the number of ranked lookups. |
| **F-17** | Low | A persistent uniqueness violation makes a status or travel request loop forever | `trade_service.rb:148` and `star_trader_ship_sync.rb:50`: `rescue ActiveRecord::RecordNotUnique; retry` with no attempt counter | A race-recovery retry written without a bound | Confirmed | `TradeService`, `StarTraderShipSync` | Bound to 2–3 attempts and re-raise after that. |
| **F-18** | Medium | One unresolvable location name disables the entire status synchronization for that client | `trade_service.rb:228-240` raises `ValidationError` → `:bad_request`; asserted by `trades_controller_test.rb:628` and `trade_service_test.rb:183` | Location resolution is treated as a request precondition rather than as one optional field among several | Confirmed (the code path; the production trigger is Probable — see §8.2) | `TradeService`, `Api::TradesController` | Degrade instead of failing: apply wallet, username, and ship association as normal; skip the location write; return 200 with an explicit `location_warning` (and `location_resolution: "unresolved"`) in the response. This single change converts the most likely cause of "status stopped updating" into a visible warning. |
| **F-19** | Medium | A legacy caller that sends `shard_uuid` without ship fields gets `400 "ship_guid is required"` | `trades_controller.rb:251-252` sets `new_status_payload` on **any one** of the five keys; `trade_service.rb:28-46` then requires **all five** | Path selection and path validation use different predicates | Confirmed | `Api::TradesController`, `TradeService` | Select the new path only when `ship_guid` is present (or when all five are), and otherwise fall through to legacy with `shard_uuid` accepted as `shard`. |
| **F-20** | Low | `deliver_ship` moves a ship with no travel guard and no player sync | `api/ships_controller.rb:88` `user_ship.update!(location_name: location.name)`; no in-transit check | A direct-write admin/bot action outside the travel subsystem | Confirmed | `Api::ShipsController` | Route it through the same location-authority service as everything else, and refuse while a travel is active. |
| **F-21** | Low | Three admin design systems; `users/show` is the only dark page in a light layout | `layouts/admin.html.erb:16` `bg-gray-100`; `users/show` (dark, `74840b5`) vs `user_ships/edit` (light, `4021768`) vs legacy index pages | Incremental restyling without a design decision | Confirmed | admin views | Adopt the `user_ships/edit` token set for the rebuild (§5.4); optionally align `users/index` afterwards. |
| **F-22** | Low | Jump arrivals always publish to the production RabbitMQ broker | `create_gate_travel!` omits `rabbitmq_environment`; `ShipTravel#normalize_rabbitmq_environment` applies `"prod"` | The environment plumbing added for `/api/travel` was not extended to gate travel | Confirmed | `GateTravelService`, `Api::GateTravelController` | Accept and thread the `rabbitmq` parameter exactly as `Api::ShipTravelController#requested_rabbitmq_environment` does. |
| **F-23** | Low | `POST /api/user_ships/:id/move` has a live `byebug` breakpoint, in production | `app/controllers/moves_controller.rb:6`; `byebug` is in the **default** Gemfile group (`Gemfile:63`), not `:development`. The action also references undefined locals `user` and `username`. `.byebug_history` (256 lines, travel/location debugging) is **tracked in git** | Debugging left in a committed, routed action | Confirmed | `MovesController`, `Gemfile`, `.gitignore` | Delete the action and its route (it duplicates `/api/travel` and cannot work), move `byebug` to `group :development`, and gitignore `.byebug_history`. |

### 8.2 Probable findings

| ID | Sev | Symptom | Evidence | Hypothesis | Conf. | What would confirm it |
|---|---|---|---|---|---|---|
| **P-01** | High | In production, the specific reason status stopped writing | §4.3 enumerates four hard-fail paths; the code for each is confirmed, but which one is firing is not observable from this checkout | F-18 (unresolvable location) is most likely, because it is the only one that is quiet server-side (`trade_service.rb:234` warn) and total client-side. F-04 is next most likely, because it presents as "the record I am watching is frozen" | Probable | Production logs: count `[TradeService.status] location_update failed`, 400/422 rates on `/api/status`, and `SELECT channel_uuid FROM shards` for case-variant duplicates |
| **P-02** | Medium | Some players' `last_location` holds legacy Minecraft `{x,y,z}` and reads as "unknown" | `current_location_name` reads no coordinate keys (`shard_user.rb:75-81`); the writer existed from `392f0c2` | Rows that predate July 2026 and have not been through `ShipAvailability#ensure_player_location_from_ship` still have coordinate-only payloads | Probable | A read-only audit of `shard_users.last_location` payload key sets (M1) |
| **P-03** | Medium | Some `shard_users.last_location` values are native jsonb objects, others double-encoded strings | The model comment says exactly this; the probe in §6.3 confirms both are readable and that native rows get rewritten on save | Mixed representation from the `coder: JSON` era plus any direct SQL writes | Probable | The same audit: `SELECT jsonb_typeof(last_location), count(*) FROM shard_users GROUP BY 1` |
| **P-04** | Medium | Duplicate or case-variant `Shard` rows already exist | F-04's mechanism is confirmed; whether it has fired is not | Clients have at some point sent a differently-cased or changed shard GUID | Probable | `SELECT lower(channel_uuid), count(*) FROM shards GROUP BY 1 HAVING count(*) > 1` |
| **P-05** | Low | Ship/player location divergence is already widespread | F-01, F-02, F-03 and F-20 all produce it, and nothing repairs it except `ensure_player_location_from_ship` (which only fires when the player is *unknown*, not when it merely disagrees) | Accumulated divergence from jumps and deliveries | Probable | The divergence count in the new admin page (M1), or a read-only reconciliation query |

### 8.3 Unresolved

| ID | Question | Why unresolved |
|---|---|---|
| **U-01** | What payload does the live StarBitizen client actually send to `/api/status`, and does it include a `location`? | The client is external to this repository. The server's presence-only logging (`trades_controller.rb:151-159`) deliberately records no values. |
| **U-02** | Which response keys does the external client depend on? | Same. This gates the F-13 fix and any non-additive change (§6.7). |
| **U-03** | How often does the tick chain actually stall in production? | `TickControl.failure_count` and `last_recovered_at` would answer it; no production access. |
| **U-04** | Are there `user_ships` rows with a `location_name` that no longer resolves to a `Location`? | Needs a database. The `has_many ... dependent: :nullify` only fires on destroy, not rename. |
| **U-05** | Do any production `shard_users` rows violate the `(user_id, shard_id)` unique index added in `20260630120000`? | The migration exists; whether it was applied cleanly is not visible here. |

---

## 9. Data consistency and risk assessment

### 9.1 Transaction boundaries today

| Operation | Transaction | Covers | Outside it |
|---|---|---|---|
| Status (new path) | `ActiveRecord::Base.transaction` (`trade_service.rb:105`) | `ShardUser` save, location write, `UserShip` save | **`Shard`, `User`, `ShardUser`, `Ship` creation**; the whole of `status_response_for` including both wallet writes and `user_ship.touch` |
| Status (legacy) | `ActiveRecord::Base.transaction` (`trade_service.rb:252`) | the two location writes | user/shard-user resolution, wallet |
| `/api/travel` | none at controller level; `ShipTravel.create!` + two `update!`s in `TravelService#call` are **separate statements** | — | everything |
| Gate travel | `ShipTravel.transaction` (`gate_travel_service.rb:129`) | travel create + ship update | the availability check and its write side effects |
| Arrival | `travel.with_lock` (`ship_travel_arrival_processor.rb:11`) — row lock **and** an implicit transaction | ship update, player update, Rabbit publish, row destroy | — |
| Cancel | `ActiveRecord::Base.transaction` (`ship_travel_controller.rb:382`) | cleanup | — |

Two specific risks follow:

* **`TravelService#call` is not atomic.** `ShipTravel.create!`, `user_ship.update!`, and `shard_user.update_current_location!` are three separate writes with no wrapping transaction. A failure in the third leaves a travel row and an `in_transit` ship with a player at the old location — F-01's symptom, reached by a different route.
* **The arrival processor publishes to RabbitMQ inside a database transaction** (`with_lock`). A slow or hanging broker holds a row lock on `ship_travels` for its duration, and a broker failure rolls back the ship and player location updates after the message may already have been delivered. `test/jobs/ship_arrival_job_test.rb:122` ("an unavailable development broker leaves the travel unprocessed instead of publishing to production") shows this is deliberate, which is defensible — but it is a database transaction waiting on a network service.

### 9.2 Concurrent writes

| Race | Current protection | Gap |
|---|---|---|
| Two simultaneous `/api/status` calls for one ship | row-level only; `find_or_initialize_by` + `save!` | both can pass, last writer wins on location; `rescue RecordNotUnique; retry` is unbounded (F-17) |
| Status concurrent with a Jump or travel | **none** | the unguarded location write (F-03) can land between travel creation and arrival |
| Two simultaneous travel creations for one ship | application checks (`travel_in_progress?`, `ShipTravel.where(...).exists?`, `active_travel.present?`) | **no database constraint**; a check-then-create race can produce two active travels for one `user_ship` |
| Two simultaneous arrivals for one travel | `travel.with_lock` + `due_for_arrival?` re-check after `reload` | correctly idempotent |
| Two simultaneous `Tick.increment!` | `pg_try_advisory_lock` in `TickRunner.with_tick_lock`, plus `tick.with_lock` | sound |
| Two `ShardUser` creations for one `(user, shard)` | unique index `20260630120000` + model validation | sound, assuming the index applied (U-05) |
| Two `Shard` creations for one logical shard | `shards.name` uniqueness only | `channel_uuid` has **no unique index** (F-04) |

The highest-value additive safety net is a **partial unique index on `ship_travels (user_ship_id) WHERE completed_at_tick IS NULL`** — except that arrival *destroys* rows rather than setting `completed_at_tick` (F-14), so `WHERE completed_at_tick IS NULL` is true for every live row and such an index would enforce "at most one travel row per ship", which is in fact the current effective invariant. That is a real option, but it interacts with F-14 and must be verified against production data before being proposed as safe.

### 9.3 Duplicate identities

| Identity | Uniqueness | Risk |
|---|---|---|
| `users.uid` | unique index | sound |
| `users.twitch_id` | **no index, no validation** | two rows can share a `twitch_id`; `find_by(twitch_id:)` then returns an arbitrary one (lowest id, via the implicit primary-key order) |
| `lower(users.username)` | unique partial index + validation | sound, but the write aborts the request (F-05) |
| `shards.channel_uuid` | **none** | F-04 |
| `shards.name` | unique | sound |
| `shard_users (user_id, shard_id)` | unique index | sound |
| `user_ships.guid` | unique index | sound; but `guid` alone is treated as ownership (F-06) |
| `ship_travels.travel_guid` | unique index + validation | sound for `/api/travel`; useless for gate travel when the client omits it |
| `ships` `model` / `slug` | **no uniqueness** | `find_or_create_status_ship!` matches on `LOWER(model)` and creates on miss, so a typo'd model creates a duplicate catalog row |

`users.twitch_id` lacking uniqueness is worth raising: it is the **primary identity key for status resolution** (`trade_service.rb:166`) and it is unconstrained.

### 9.4 Stale records

* `user_ships.location_name` is a **name string**, not a foreign key. Renaming a `Location` orphans every ship there with no error; `Location`'s `dependent: :nullify` only fires on destroy. `shard_users.last_location["name"]` has the same exposure, with the extra wrinkle that `last_location["id"]` is also stored and can disagree with `["name"]` after a rename. The admin UI should show "does this name still resolve?" for exactly this reason (§5.4 C).
* `Location#preserve_calibrated_identity` and `#protect_calibration_record` prevent renaming or deleting *calibrated* locations, which covers the orbital catalog but not the general case.
* Arrived travels are destroyed, so "no travel row" is indistinguishable from "never travelled" (F-14).
* `ShipTravel.cleanup_stale_after_arrival!` runs every tick and destroys travels whose `arrival_tick` has passed, setting the ship to `"aimlessly floating in space"` **without updating either location** — a third path by which a ship ends up somewhere its travel row no longer explains.

### 9.5 Recovery

Tick recovery is the most mature part of the system: `TickJob` self-chains, `TickWatchdogJob` re-schedules every 30 s when `pending_count` is zero or the heartbeat is stale, `TickControl` records failures and recoveries, and `TickRunner` serializes with a PostgreSQL advisory lock. Arrival recovery is also sound: `ShipArrivalJob` sweeps every tick for `arrival_tick <= current_tick AND arrival_tick != 0 AND NOT is_paused AND completed_at_tick IS NULL`, and `ShipTravelArrivalProcessor` is idempotent under `with_lock` (`ship_arrival_job_test.rb:57`).

There is **no recovery for location divergence.** Nothing detects or repairs a `(shard_user, user_ship)` pair that disagrees. `ShipAvailability#ensure_player_location_from_ship` only fires when the player location is *unknown*, never when it merely differs — and when it differs, `validate_usable!` **blocks the player from travelling or trading at all** (`"Ship is at X, but player is at Y."`). So an F-01 divergence is not a cosmetic reporting bug: it soft-locks the player until an admin or a `*status` call at the right place resolves it. That is the strongest reason to treat objective 4 as the highest-priority repair.

### 9.6 Migration risks for the proposed work

| Proposed change | Risk | Mitigation |
|---|---|---|
| Normalize + unique-index `shards.channel_uuid` | existing case-variant duplicates make the index creation fail; merging shards means merging `ShardUser`, `UserShip`, `ShipTravel` and wallets | audit first (M1); merge deliberately with a reviewed data task; `CREATE INDEX CONCURRENTLY` |
| Add `shard_users.location_updated_at`, `location_source` | none — additive, nullable | backfill `location_updated_at` from `updated_at` only if the operator accepts it as approximate, otherwise leave NULL and label it "never recorded" |
| Drop the `last_location` store coder (F-07) | **high** — a half-migrated column breaks `current_location_name` for whichever representation is not handled | keep the read normalizer permanently; backfill in one task; only then add a GIN index. Defer; it is not the reported regression |
| Backfill divergent player locations | choosing the wrong winner silently teleports a player | reuse `lib/tasks/ship_locations.rake`'s conservative pattern: only write where the player location is **absent**; report, do not auto-resolve, where the two merely differ |
| Fix F-02 (reject jumping from a gateway you are not at) | four committed tests assert the current teleport; a bot that relies on it starts failing | owner decision (§14 Q2); if accepted, update the tests in the same commit and announce the client-visible change |
| Fix F-13 (paused countdown) | the external client may special-case `0` | additive first, then announce (§6.7) |
| Fix F-12 (15 000 grant) | players who currently farm the refund lose it | owner decision; it is a gameplay change, not a bug fix, from the player's point of view |
| Add `arrival_at_unix` | none — additive | — |

---
## 10. Recommended architecture

### 10.1 The one structural change

Replace seven ad-hoc location writers with **one service that owns both location fields and decides authority**. Everything else in this report is a consequence.

```
                        ┌──────────────────────────────────────────────┐
  POST /api/status ────▶│ TradeService.status                          │
                        │  identity: twitch_id → User                  │─┐
  POST /api/travel ────▶│ StarTraderShipSync                           │ │
                        │  identity: twitch_id → User (strict)         │─┤
  POST /api/gate_travel │ GateTravelService                            │ │
         (Jump) ───────▶│  identity: user_ship.guid → User             │─┤
                        │                                              │ │
  ShipArrivalJob ──────▶│ ShipTravelArrivalProcessor                   │─┤
  (every tick)          └──────────────────────────────────────────────┘ │
                                                                         ▼
                                      ┌────────────────────────────────────────────┐
                                      │  LocationSync  (new, single writer)        │
                                      │                                            │
                                      │  authority order:                          │
                                      │   1. active or paused ShipTravel  (server) │
                                      │   2. arrival processing           (server) │
                                      │   3. travel initiation            (server) │
                                      │   4. client *status observation   (client) │
                                      │   5. repair from the other record (fallback)│
                                      │                                            │
                                      │  writes, in ONE transaction:               │
                                      │   • user_ships.location_name               │
                                      │   • shard_users.last_location (merged)     │
                                      │   • shard_users.location_updated_at        │
                                      │   • shard_users.location_source            │
                                      │  and logs every rejected write             │
                                      └────────────────────────────────────────────┘
```

Rules the service enforces, each traceable to a finding:

1. **A server-authoritative journey outranks a client observation.** While an `active_status_travel` exists (`completed_at_tick IS NULL AND (is_paused OR arrival_tick > current_tick)` — the predicate that correctly includes interdicted travel), a client-reported location is recorded as an observation and **not** applied to either field. Fixes F-03. Status still returns 200 with the authoritative travel state (§4.6 requirement preserved).
2. **Travel initiation normalizes the player to the journey origin, always.** `TravelService` already does this; `GateTravelService` must. Fixes F-01's departure half.
3. **Arrival moves ship and player together, unconditionally, in one transaction.** The equality guard becomes unnecessary once rules 1 and 2 hold: the player is at the origin by construction, and no client write can have intervened. Fixes F-01's arrival half and removes the fragile condition at `ship_travel_arrival_processor.rb:48`.
4. **A journey's origin must be where the ship actually is.** Fixes F-02 (subject to §14 Q2).
5. **Blank or unresolvable client location never destroys a good value.** Blank already short-circuits correctly; unresolvable must degrade to a 200-with-warning instead of a 400. Fixes F-18.
6. **Every write records who wrote it and when** (`location_source` ∈ `client_status | travel_departure | travel_arrival | repair | admin`, plus `location_updated_at`). This is the instrumentation the admin diagnostics panel needs (§5.4 E) and the only way to tell, afterwards, which rule applied.
7. **Named locations only.** `update_current_location!` keeps merging into the existing payload so legacy coordinate keys survive untouched, and nothing synthesizes coordinates. Fixes nothing by itself; prevents F-08 from being made worse.

### 10.2 Source of truth per field

| Field | Source of truth | Written by | Never written by |
|---|---|---|---|
| `users.twitch_id`, `users.uid` | client at first contact, then **immutable** | status (create only) | anything, after creation |
| `users.username` | client via status, **best-effort** | status, with conflicts rescued and reported (F-05) | — |
| `users.wallet_balance` | legacy platform field, **not gameplay** | admin only | the API |
| `shards.channel_uuid` | external shard identity, normalized | admin; status create-on-miss only if the owner keeps it (§14 Q3) | — |
| `shard_users.wallet_balance` | **client via status** | status; trades | — |
| `shard_users.last_location` | **server while a journey exists, client otherwise** | `LocationSync` only | every current direct caller |
| `shard_users.location_updated_at` / `location_source` | derived | `LocationSync` only | — |
| `shard_users.karma` / `fame` / `murder_count` / `stats` | server | `adjust_stats`, admin | — |
| `user_ships.location_name` | **server while a journey exists, client otherwise** | `LocationSync` only | `deliver_ship` directly (F-20) |
| `user_ships.status` | **travel subsystem** | travel services, arrival processor, interdict/resume, `Tick#correct_ship_statuses` | status |
| `user_ships.user_id` / `shard_id` / `shard_user_id` | one policy, applied by both endpoints | per §14 Q4 | — |
| `ship_travels.*` ticks | **travel subsystem, absolutely** | `TravelService`, `GateTravelService`, `interdict!`, `resume!` | status, admin |
| `ticks.current_tick` | `TickRunner` under advisory lock | `Tick.increment!` | unauthenticated HTTP (F-10) |
| derived `arrival_at_unix` | computed per response, never stored | serializers | — |

### 10.3 Integration contract

**`POST /api/status`** — unchanged keys, three additions, no removals:

```
{ status, wallet_balance, player_location, ship: {...}, ships: [...], cargo: [...],
  // when a travel exists (active or paused), unchanged:
  ship_status: "in_transit", message, ship_guid, ship_model, current_location,
  travel: { travel_guid, from_location, to_location, departure_tick, arrival_tick,
            current_tick, remaining_ticks, time_remaining, is_paused,
            arrival_at_unix          // NEW: integer epoch seconds, null when paused
          },
  location_resolution: "applied" | "unresolved" | "ignored_in_transit" | "absent",   // NEW
  warnings: [ { code: "location_unresolved" | "username_conflict" | "shard_created", message } ]  // NEW
}
```

**`POST /api/gate_travel`** — unchanged keys plus `arrival_at_unix`, `player_location`, and `rabbitmq` support; `current_tick` keeps its (mislabelled) value for compatibility and gains a correctly named `departure_tick`.

**`POST /api/travel`** — unchanged plus `arrival_at_unix`.

**RabbitMQ `ShipArrival`** — **unchanged.** It is a positional pipe-delimited string consumed by an external bot (`rabbitmq_sender.rb:35-49`); adding a field shifts every index. Leave it alone.

### 10.4 Administrative reporting

The admin user view becomes the read model over this architecture: it reads `last_location` + `location_updated_at` + `location_source` per shard, `location_name` + travel per ship, and shows agreement explicitly. Divergence becomes a visible, countable condition rather than an inferred one — which is what makes the repair verifiable in production (§13 M1 before M2).

---

## 11. Acceptance criteria

### Objective 1 — `/api/status` synchronization

1. Given an existing user, shard, and ship, a status call with a resolvable `location` persists `shard_users.last_location["name"]` and `user_ships.location_name` to that location and returns 200. *(already true; must stay true)*
2. Given a status call with **no** `location`, no location field changes and the response reports the existing `player_location`. *(already true; must stay true)*
3. Given a status call whose `location` cannot be resolved, the response is **200**, `location_resolution == "unresolved"`, a `location_unresolved` warning is present, the existing location fields are unchanged, and `wallet_balance`, `users.username`, and the ship's shard association **are** applied. *(changes F-18's 400)*
4. Given a status call whose `player_name` collides case-insensitively with another user, the response is **200**, `users.username` is unchanged, a `username_conflict` warning is present, and the location and wallet writes are applied to the `twitch_id`-resolved user. The other user's record is untouched. *(changes F-05's 422)*
5. Given a `shard_uuid` that differs from an existing `shards.channel_uuid` only in case or surrounding whitespace, the existing `Shard` is matched; no new `Shard` or `ShardUser` is created.
6. Given a ship in transit and a status call reporting a **different** location, neither `last_location` nor `location_name` changes, the response is 200, `location_resolution == "ignored_in_transit"`, and the travel row is byte-identical afterwards.
7. Given a ship interdicted (`is_paused: true`, `arrival_tick: 0`), the response is 200, `travel.is_paused == true`, `travel.arrival_tick == 0`, `travel.remaining_ticks == remaining_ticks_from_arrival`, `travel.arrival_at_unix == nil`, and **`ship.time_remaining` equals `travel.time_remaining`**.
8. A status call never creates, modifies, or destroys a `ShipTravel` row.
9. A legacy `username` + `shard` payload still works; a `username` + `shard_uuid` payload is accepted on the legacy path rather than rejected for a missing `ship_guid`.
10. All of the ~60 existing status tests still pass, except those that assert the 400/422 behaviours deliberately changed by criteria 3 and 4, which are rewritten in the same commit.

### Objective 2 — Admin user view

11. `/admin/users/:id` shows every `ShardUser` with shard name, `channel_uuid`, per-shard wallet, karma, fame, murder count, and member-since.
12. For each `ShardUser` it shows the named celestial location, star system, classification, whether the name still resolves to a `Location`, and the raw `last_location` payload; a legacy coordinate row is shown **only** when `x`/`y`/`z` are actually present, labelled as legacy.
13. For each `UserShip` it shows model, slug, GUID, shard, status, current location, cargo, and — when a travel row exists — from/to, departure and arrival ticks, current tick, remaining ticks, paused state, interdiction count, and RabbitMQ environment.
14. An interdicted ship shows `arrival_tick` as `0 (interdicted)`, a remaining time derived from `remaining_ticks_from_arrival`, and **no** countdown to tick 0.
15. A ship/player location mismatch is shown explicitly, per pair, and counted in a header chip.
16. Missing data renders as a distinguishable label (`Unknown`, `Not recorded`, `Not tracked`, `No journey on record`) and is never rendered as `0`, `—` for a real zero, or an empty string.
17. Every timestamp renders with an explicit timezone abbreviation.
18. The page issues **no query inside a `shard_users`, `user_ships`, or `ship_travels` loop**: verified by `assert_queries_count` or an equivalent bound on a fixture with 3 shards and 8 ships.
19. A non-admin signed-in user is redirected from `/admin/users/:id` and `/admin/users`; an anonymous request is redirected to login. Both are covered by tests.
20. No credential (`secret_guid`, API token) appears in the rendered page, and no third-party request carries `user.uid`.
21. The page uses the `admin/user_ships/edit` token set and renders correctly inside the `bg-gray-100` admin layout.

### Objective 3 — Timestamps

22. Every absolute instant in an API response is an integer Unix epoch seconds field whose key ends in `_at_unix`, or JSON `null`.
23. No `_tick` field changes type, name, or meaning. `arrival_tick = 0` still means interdicted, and `ShipArrivalJob`, `ShipAvailability#process_due_arrival!`, `process_due_arrival_for`, `due_for_arrival?` and `stale_after_arrival` still exclude it.
24. `arrival_at_unix` is present and plausible for an in-flight travel (`Time.current + remaining_ticks * seconds_per_tick`, ±1 s), and `null` for a paused one.
25. `arrival_at_unix` is never persisted and no arrival decision reads it; arrival remains `arrival_tick <= Tick.current`.
26. Durations keep `_seconds`; tick counts keep `_ticks`; the suffix rule in §6.5 holds across every touched serializer.
27. Travel speed, distance, tick cadence, `TravelTiming::SPEED_GM_PER_TICK`, `MINIMUM_DURATION_TICKS`, interdiction window percentages, and interdiction/resume behaviour are byte-identical; `test/services/travel_timing_pipeline_test.rb` and the orbital tests pass unchanged.
28. A test freezing time across a DST boundary in a non-UTC display zone shows that stored values and tick arithmetic are unaffected and only the display string changes.
29. The RabbitMQ `ShipArrival` message format is byte-identical.

### Objective 4 — Jump

30. A Jump from a gateway the ship is at sets `user_ships.location_name` **and** `shard_users.last_location` to that gateway, in one transaction, and creates exactly one `ShipTravel` with `ship_travel_type: "gate_travel"`.
31. On arrival, **both** `user_ships.location_name` and `shard_users.last_location` become the destination gateway, regardless of what the player's location was beforehand.
32. A Jump naming a gateway the ship is not at is **rejected** with a clear message, and neither location field changes. *(subject to §14 Q2)*
33. A Jump while travelling, while interdicted, or while ship and player are not co-located is rejected and changes nothing.
34. A Jump by a ship with no `shard_user` returns a clear domain error, not a `NoMethodError` message.
35. Repeating a Jump with the same `travel_guid` returns the existing travel and creates no second row; omitting `travel_guid` is rejected, as `/api/travel` already does.
36. A status call during a Jump does not change either location field, and the Jump still lands the player correctly at arrival.
37. After arrival, a status call reports ship and player at the same destination with `available_at_player_location: true`.
38. A Jump accepts and persists `rabbitmq=dev`, and the arrival publishes to that broker.
39. Interdicting a gate travel sets `arrival_tick = 0`; resuming restores a real arrival tick; neither changes either location field.

---

## 12. Test strategy

### 12.1 Framework

Minitest, `ActiveSupport::TestCase` with `parallelize(workers: :number_of_processors)` and `fixtures :all` (`test/test_helper.rb`). Fixtures are nearly empty (`settings.yml` is scaffold junk, `ship_travels.yml` is a comment), so every meaningful test builds its own world in `setup` with `delete_all` + `create!` — that is the established convention and should be followed. Helpers available: `test/support/integration_sign_in.rb` (`sign_in_as`, `sign_in_admin` through the real OmniAuth callback), `test/support/orbital_fixtures.rb` (`seed_orbital_catalog`), `test/support/no_real_broker.rb`, `test/support/terminal_market_fixtures.rb`, `test/support/read_only_foreign_key_check.rb`.

**Run them with `bin/codex_test` (optionally with paths), not `bin/rails test`** — the README is explicit, and the wrapper pins Ruby 3.2.2 through rbenv, runs `db:prepare`, and classifies failures.

### 12.2 Existing coverage

| Area | File | Strength |
|---|---|---|
| Status, controller level | `test/controllers/api/trades_controller_test.rb:443-910` (~30 tests) | **strong**: payload shapes, nested `trade`, auth, all five required fields, location applied/absent/unknown, per-ship targeting, idempotency, unknown shard/ship/user creation, ship overwrite, wallet validation, in-transit payload |
| Status, service level | `test/services/trade_service_test.rb:106-546` (~30 tests) | **strong**: same ground plus serialized-data preservation, association restoration, the username-conflict raise, the 15 000 grant |
| Normal travel | `test/controllers/api/ship_travel_controller_test.rb` (1588 lines) | strong |
| Gate travel | `test/controllers/api/gate_travel_controller_test.rb` (414 lines, 21 tests) | **broad but wrong-shaped** — covers gateway naming, system scoping, ambiguity, auth, arrival; **asserts the ship teleport (F-02) and asserts nothing about `shard_user` (F-01)** |
| Arrival + broker routing | `test/jobs/ship_arrival_job_test.rb` (8 tests) | strong: skipped arrivals, idempotency, paused exclusion, per-environment routing, interdict-then-resume |
| `ShardUser` | `test/models/shard_user_test.rb` (6 tests) | good: duplicate prevention at both levels, cascade destroy, duplicate cleanup/merge, **and `:131` "JSON stores read and preserve both native and legacy string representations"** |
| Travel env | `test/services/travel_service_test.rb` (6 tests) | covers only `rabbitmq_environment` |
| Tick | `test/jobs/tick_job_test.rb`, `tick_watchdog_job_test.rb`, `test/services/tick_runner_test.rb`, `test/models/tick_test.rb` | good on scheduling and recovery |
| Admin authz | `test/controllers/admin/access_test.rb` (2 tests) | **data importers only** |

### 12.3 Gaps, mapped to the brief's matrix

| Area | Required scenario | Covered? | Proposed test |
|---|---|---|---|
| Status sync | existing user / new user / existing shard / new shard / existing ship / missing ship | **yes, all six** | — |
| Identity | stable GUID matching | yes (`trade_service_test.rb:106`, `:420`) | — |
| Identity | username casing | **partly** — only the raise (`:449`) | status with a case-variant colliding `player_name` applies location and wallet, returns 200 + warning, leaves both usernames intact |
| Identity | duplicate names | **no** | two `User` rows with the same `lower(username)` cannot exist (index); instead assert `find_by(twitch_id:)` picks correctly when two users share a `twitch_id` (§9.3) |
| Identity | shard scoping | yes (`trades_controller_test.rb:778`, `trade_service_test.rb:530`) | add: `shard_uuid` differing only in case matches the existing shard and creates nothing |
| Location | valid coordinates | n/a by design (§6.4) | assert `update_current_location!` **preserves** pre-existing `x`/`y`/`z` keys while setting `name` |
| Location | blank coordinates | yes (`:618`) | — |
| Location | missing coordinates | yes | — |
| Location | malformed JSON | **no** | `ShardUser` with `last_location` = a bare JSON string, an array, and `null` → `current_location_name` returns nil and nothing raises |
| Persistence | successful update | yes | — |
| Persistence | validation failure | **partly** | status where `ShardUser` fails validation → the whole transaction rolls back, `user_ships.location_name` unchanged |
| Persistence | rollback | **no** | force `assign_authoritative_status_user_ship!` to raise → assert `last_location` is unchanged (proves the transaction boundary) |
| Persistence | repeated requests | yes (`:885`, `:464`, `:476`) | — |
| Travel | idle | yes | — |
| Travel | in transit | **partly** — only the non-conflicting location | **status in transit with a conflicting location leaves both fields unchanged and the travel row untouched** (the F-03 regression test) |
| Travel | interdicted | **no status coverage** | status for an interdicted ship: 200, `arrival_tick == 0`, `is_paused`, remaining from `remaining_ticks_from_arrival`, `ship.time_remaining == travel.time_remaining` |
| Travel | resumed | yes (`ship_arrival_job_test.rb:140`) | add the status-response assertion after resume |
| Travel | arrived | yes | — |
| Jump | success | **partly** | **`shard_users.last_location` becomes the origin gateway at departure** (the F-01 regression test) |
| Jump | rejection | yes (`:319`, `:302`, `:309`) | add: jumping from a gateway the ship is not at is rejected and nothing moves (F-02) |
| Jump | retry | **no** | same `travel_guid` twice → one travel; omitted `travel_guid` → rejected |
| Jump | duplicate | **partly** (`"Already in transit"`) | explicit assertion plus the interdicted case |
| Jump | concurrency | **no** | two threads jump the same ship → exactly one `ShipTravel` (document as best-effort without a DB constraint) |
| Jump | arrival | yes for the ship (`:331`) | **extend to assert `shard_users.last_location` becomes the destination even when it did not equal the origin** |
| Time | UTC conversion | **no** | `Time.zone` is UTC; `*_at_unix` == `record.created_at.to_i` |
| Time | DST boundaries | **no** | freeze at a US DST transition, render admin timestamps in a non-UTC display zone, assert the stored value and all tick arithmetic are unchanged |
| Time | seconds/ms | **no** | `arrival_at_unix` is in seconds (10 digits for current dates) and `arrival_at_unix - Time.current.to_i == remaining_ticks * seconds_per_tick` |
| Time | tick vs epoch | **no** | `arrival_tick` is a small integer and `arrival_at_unix` a 10-digit epoch; interdicted → `arrival_tick == 0` **and** `arrival_at_unix == nil` (never `0` and never 1970) |
| Admin UI | multiple shards | **no** | 3 shards × ships, all rendered, correct per-shard wallet |
| Admin UI | multiple ships | **no** | 8 ships grouped under their shards with a bounded query count |
| Admin UI | missing data | **no** | a user with no `ShardUser`, a `ShardUser` with `last_location == {}`, a ship with `location_name == nil` → explicit labels, no exception |
| Admin UI | stale data | **no** | `last_location["name"]` pointing at a non-existent `Location` → "stale" badge |
| Admin UI | authorization | **no** | anonymous → login; player → root; admin → 200 |

### 12.4 Reproduction procedures (all isolated; none executed in this session)

Each runs against the test database via `bin/codex_test`. No production reads or writes, no deployment.

**R-1 — Jump leaves the player behind (F-01, F-02).** The cheapest reproduction is to add one assertion to an existing test:

```ruby
# test/controllers/api/gate_travel_controller_test.rb, inside
# test "ship in Pyro can enter Nyx Gateway without parenthetical suffix"
@user_ship.update!(location_name: @pyro_location.name)
post_gate_travel(ship_guid: @user_ship.guid, gateway_name: "Nyx Gateway")
assert_equal @nyx_gateway_in_pyro.name, @user_ship.reload.location_name  # passes today
assert_equal @nyx_gateway_in_pyro.name, @shard_user.reload.current_location_name  # EXPECTED TO FAIL today

travel = ShipTravel.find_by!(travel_guid: response_json["travel_guid"])
Tick.instance.update_columns(current_tick: travel.arrival_tick, sequence: travel.arrival_tick)
RabbitmqSender.stub(:send_ship_report, ->(_t) {}) { ShipArrivalJob.perform_now }
assert_equal @pyro_gateway_in_nyx.name, @user_ship.reload.location_name            # passes today
assert_equal @pyro_gateway_in_nyx.name, @shard_user.reload.current_location_name   # EXPECTED TO FAIL today
```

Predicted outcome from code reading: both player assertions fail, the second because `update_player_location_if_travel_origin_matches!` compares "Ruin Station" with "Nyx Gateway (Pyro)". **Not executed.**

**R-2 — Status overwrites an in-flight location (F-03).** Build on `trades_controller_test.rb:562` but pass a *different* location:

```ruby
# ship in transit @location → destination; report a third location
post "/api/status", params: base_status_payload.merge(location: third_location.name), as: :json
assert_response :success
assert_equal @location.name, @shard_user.reload.current_location_name   # EXPECTED TO FAIL today
assert_equal @location.name, @user_ship.reload.location_name            # EXPECTED TO FAIL today
assert_equal travel_attributes, travel.reload.attributes                # passes today
```

**R-3 — Unresolvable location kills the whole sync (F-18).**

```ruby
@shard_user.update_current_location!(@location)
post "/api/status", params: base_status_payload.merge(location: "Not A Real Place", wallet_balance: 99_999), as: :json
assert_response :success                                     # EXPECTED TO FAIL today (400)
assert_equal 99_999, @shard_user.reload.wallet_balance       # EXPECTED TO FAIL today
assert_equal @location.name, @shard_user.current_location_name
```

**R-4 — Case-variant shard creates a sibling record (F-04).**

```ruby
assert_no_difference ["Shard.count", "ShardUser.count"] do
  post "/api/status", params: base_status_payload.merge(shard_uuid: @shard.channel_uuid.upcase), as: :json
end                                                          # EXPECTED TO FAIL today (+1 each)
```

**R-5 — Username collision aborts everything (F-05).**

```ruby
other = User.create!(username: "Collider", twitch_id: "other-twitch", uid: "other-uid", user_type: "player")
post "/api/status", params: base_status_payload.merge(player_name: "COLLIDER", wallet_balance: 77_777), as: :json
assert_response :success                                     # EXPECTED TO FAIL today (422)
assert_equal 77_777, @shard_user.reload.wallet_balance       # EXPECTED TO FAIL today
assert_equal "TestPilot", @user.reload.username
assert_equal "Collider", other.reload.username
```

**R-6 — Interdicted countdown contradiction (F-13).**

```ruby
travel.interdict!(Tick.current)   # arrival_tick → 0, is_paused → true
post "/api/status", params: base_status_payload, as: :json
assert_response :success
assert_equal 0, response_json.dig("travel", "arrival_tick")
assert_operator response_json.dig("travel", "time_remaining"), :>, 0
assert_equal response_json.dig("travel", "time_remaining"),
             response_json.dig("ship", "time_remaining")      # EXPECTED TO FAIL today (ship → 0)
```

**R-7 — `last_location` storage audit (read-only, needs a database).** Not reproducible from this checkout; listed so it is not forgotten:

```sql
SELECT jsonb_typeof(last_location) AS stored_as, count(*) FROM shard_users GROUP BY 1;
SELECT count(*) FROM shard_users WHERE last_location = '{}'::jsonb OR last_location IS NULL;
SELECT lower(channel_uuid), count(*) FROM shards GROUP BY 1 HAVING count(*) > 1;
SELECT count(*) FROM user_ships us
  LEFT JOIN locations l ON l.name = us.location_name
  WHERE us.location_name IS NOT NULL AND l.id IS NULL;
```

Because of F-07 the first query will mostly report `string`, not `object`. Key-set inspection must therefore happen in Ruby (`ShardUser.find_each { |su| su.last_location.keys }`), not in SQL.

### 12.5 Required regression tests (the minimum that must exist when the work lands)

1. R-1 (Jump departure + arrival player location) — guards F-01.
2. R-2 (status in transit with a conflicting location) — guards F-03.
3. R-3 (unresolvable location degrades, does not abort) — guards F-18.
4. R-4 (case-variant shard) — guards F-04.
5. R-5 (username conflict degrades) — guards F-05.
6. R-6 (paused countdown consistency) — guards F-13.
7. Jump from a non-co-located gateway is rejected — guards F-02.
8. `arrival_at_unix` present in flight, `null` when paused, never `0` — guards objective 3 criteria 24 and 25.
9. Admin page: 3 shards × 8 ships, bounded query count, explicit missing-data labels, stale-location badge — guards objective 2.
10. Admin authorization: anonymous, player, admin — guards criterion 19.
11. The whole existing suite, unchanged except where criteria 3, 4 and 7 deliberately invert an asserted behaviour.

---

## 13. Proposed milestone sequence

Preliminary. The playbook assignment should refine it. Dependencies are strict.

### M1 — Observability and audit (read-only)

* **Objective**: make the current state visible before changing it, and replace the Probable findings in §8.2 with measurements.
* **Dependencies**: none.
* **Expected changes**: rebuild `app/views/admin/users/show.html.erb` per §5.4 with the `user_ships/edit` token set; add `shard_users` and `ship_travels` preloading plus a single batched `Location` name lookup to `Admin::UsersController#set_user`; add a read-only diagnostics panel (including `TickControl`); add a `ShardUsers` sidebar link; add a read-only rake task that reports `last_location` payload key sets, `jsonb_typeof` distribution, case-variant `shards.channel_uuid` groups, unresolvable `user_ships.location_name` values, and ship/player divergence counts.
* **Verification**: admin tests for multiple shards/ships, missing data, stale data, bounded query count, and authorization (criteria 11-21); the audit task run against a seeded isolated database; `bin/codex_test` green.
* **Completion**: an admin can open any user and see every shard membership, every ship, both location values, and whether they agree; the audit output answers P-02 through P-05.
* **Risks / rollback**: read-only, so the risk is a rendering error on unusual data (nil `shard_user`, `last_location` holding a bare string, a `location_name` that no longer resolves) — cover each in a test. Rollback is reverting one view and one controller.

### M2 — Jump location synchronization

* **Objective**: F-01, F-15, F-22, and F-02 if the owner accepts §14 Q2.
* **Dependencies**: M1 (so the fix is verifiable), plus the Q2 decision.
* **Expected changes**: `GateTravelService#create_gate_travel!` calls `user_ship.shard_user&.update_current_location!(origin_location)` inside its existing transaction; nil-guard `ShipAvailability#ensure_player_location_from_ship`; thread `rabbitmq` through `Api::GateTravelController`; add the co-location check if Q2 says yes, updating the four tests that currently assert the teleport; require `travel_guid`.
* **Verification**: R-1 passes; the gate-travel suite passes with its updated assertions; `test/jobs/ship_arrival_job_test.rb` unchanged and green.
* **Completion**: criteria 30-35, 38, 39.
* **Risks / rollback**: the co-location check is client-visible and may break a bot workflow that currently relies on teleporting to a gateway — hence the owner gate. The player-location write alone is additive and safe. Rollback is one service file.

### M3 — Status authority model

* **Objective**: F-03, F-18, F-05, F-19, F-17, and the arrival guard simplification.
* **Dependencies**: M2 (so arrival-side behaviour is already correct), plus decisions Q1 and Q3.
* **Expected changes**: extract `LocationSync` as the single writer (§10.1) and route `TradeService`, `TravelService`, `GateTravelService`, `ShipTravelArrivalProcessor`, `ShipAvailability`, `Api::ShipTravelController` and `Api::ShipsController#deliver_ship` through it; make `resolve_status_location!` non-fatal; rescue the username rename; normalize `channel_uuid`; fix the new/legacy path predicate; bound both `retry` loops; replace the arrival equality guard with the authority rule; add `location_resolution` and `warnings` to the status response.
* **Verification**: R-2 through R-5 pass; all ~60 existing status tests pass except the two that assert the deliberately changed 400/422, rewritten in the same commit; `/api/travel` and gate-travel suites unchanged and green.
* **Completion**: criteria 1-10.
* **Risks / rollback**: the largest behavioural surface in the series. Two responses change status code (400→200, 422→200) — strictly more permissive, so no client that works today breaks, but the warning keys are new. Rollback is reverting the service extraction; do it as one reviewable commit, not several.

### M4 — Timestamp standardization (additive)

* **Objective**: objective 3, additively.
* **Dependencies**: M3 (so the status serializer is settled), plus decisions Q5 and Q6.
* **Expected changes**: a shared `estimated_arrival_at`/`arrival_at_unix` derivation on `ShipTravel`; add `arrival_at_unix` to status, `/api/travel`, `/api/gate_travel`, `/api/location`; fix the paused `ship.time_remaining`/`ship.arrival_tick` contradiction (F-13); label timezones in every admin view and convert the hardcoded Pacific conversion to a setting; document the `_tick`/`_ticks`/`_seconds`/`_at_unix`/`_at` rule in the README.
* **Verification**: criteria 22-29; the DST and seconds-vs-milliseconds tests; `test/services/travel_timing_pipeline_test.rb` and all orbital tests byte-identical in behaviour; the Rabbit message format asserted unchanged.
* **Completion**: criteria 22-29.
* **Risks / rollback**: only F-13 is non-additive, and the external client may special-case `0` — announce it, or ship it behind the warning mechanism added in M3. Rollback is per-serializer.

### M5 — Location instrumentation (first schema change)

* **Objective**: close the §5.4 E gap — *last location update*, *source of the recorded location*, and real synchronization warnings.
* **Dependencies**: M3.
* **Expected changes**: one additive migration adding `shard_users.location_updated_at` (datetime, nullable) and `shard_users.location_source` (string, nullable); `LocationSync` writes both; the admin diagnostics panel reads both; no backfill (NULL renders as "never recorded").
* **Verification**: each source value is produced by its path; the admin panel renders correctly for NULL; the migration is reversible.
* **Completion**: the operator can tell *when* and *by which authority* a player's location last changed.
* **Risks / rollback**: additive and nullable, so rollback is a `down` migration. Do **not** combine with the F-07 re-encoding — that is a separate, riskier migration and is not required by any of the four objectives.

### M6 — Hygiene and hardening (optional, independent)

* **Objective**: F-08, F-10, F-11, F-12, F-20, F-21, F-23, and the `users.twitch_id` uniqueness gap.
* **Dependencies**: none, but sequence it last so it never blocks a repair.
* **Expected changes**: delete `Api::ShardUsersController`, `MovesController`, and `Api::CommandsController#travel` with their routes; move `byebug` to `group :development` and gitignore `.byebug_history`; authenticate or delete `Api::TickController`; narrow `resources :users` and drop the two `minecraft_uuid` routes; move the 15 000 grant to record creation; route `deliver_ship` through `LocationSync`; optionally align `admin/users/index` to the light token set; consider a unique index on `users.twitch_id` after an audit.
* **Verification**: a full `bin/codex_test` run; route coverage check; a test that `POST /api/increment_tick` without credentials is rejected.
* **Completion**: no routed action references a removed column, no debugger ships in production, no unauthenticated tick mutation.
* **Risks / rollback**: deletions are the risk — confirm from production logs that nothing calls these routes before removing them. F-12 is a gameplay change and needs the owner's sign-off.

---

## 14. Open questions and decision register

### Decisions I can defend from repository evidence (proceed on these unless the owner objects)

| ID | Question | Recommendation | Evidence |
|---|---|---|---|
| **D1** | Does `last_location` store coordinates or a named location? | **Named location.** Keep the `update_current_location!` payload; keep merging so legacy keys survive; add no coordinate tracking. | `git log -S "last_location" -- app` → only `392f0c2` (dead Minecraft writer) and `09862f0` (named writer); `current_location_name` reads no coordinate keys (§6.4) |
| **D2** | Should `ShardUser.current_location` become a column? | **No.** Keep it derived from `last_location`; batch the `Location` lookups in the admin controller. | there has never been such a column (`schema.rb:418-435`); a second stored copy would add a fifth competing truth |
| **D3** | Which design system for the rebuilt admin page? | **The light-modern token set from `admin/user_ships/edit.html.erb`.** | newest detail page (2026-06-30 `4021768` vs 2026-06-12 `74840b5`); only one with a complete sectioned layout; the only one matching the `bg-gray-100` layout |
| **D4** | Should an absolute arrival timestamp be exposed? | **Yes, as a derived, never-persisted `arrival_at_unix`, `null` when paused.** `arrival_tick` is untouched. | ticks are not a uniform wall clock (`TickWatchdogJob`, `TickControl.failure_count`); `null` is the only honest representation of the `arrival_tick = 0` sentinel on the Unix axis (§6.6) |
| **D5** | Should `last_location`'s double encoding be fixed now? | **No.** Document it, surface the raw payload in admin, defer the re-encoding to its own milestone. | the probe in §6.3 shows it is longstanding and not the reported regression; a half-migrated column would break `current_location_name` (§9.6) |
| **D6** | Should `completed_at_tick` be revived? | **No, not in this series.** Label "no travel row" as "No journey on record". | reviving it changes every active-travel predicate in six places (F-14) |

### Questions that materially require the owner

| ID | Question | Why it needs the owner | My recommendation |
|---|---|---|---|
| **Q1** | What does a client-reported location mean while the server holds an active or paused travel — ignore it, apply it, or treat a persistent disagreement as evidence the server is wrong? | A gameplay-authority decision. Ignoring is safest but will feel "stuck" to a player who really did move; applying it is what causes F-01/F-03. | **Ignore while in flight, and report the divergence in the response and the admin panel.** If it turns out players legitimately move mid-flight, add an explicit "disembark" action rather than inferring it from a status report. |
| **Q2** | May a Jump name a gateway the ship is not currently at, teleporting it there? | Four committed tests assert this behaviour, so it may be an intentional convenience the live bot depends on. Changing it is client-visible. | **Reject it** (criterion 32). It is the direct cause of F-02 and half of F-01, and `/api/travel` already refuses the analogous mismatch (`"from_location does not match the player's current location."`). If the convenience is wanted, it should be an explicit two-step or an explicit `allow_reposition` flag. |
| **Q3** | May `/api/status` keep silently creating `Shard` rows for unknown `shard_uuid`s? | Convenience for new live shards versus the record-splitting in F-04. Two committed tests assert the creation. | **Keep creating, but normalize `channel_uuid` (strip + case-fold) on read and write, add a unique index, and surface a `shard_created` warning** in the response and the admin panel so it is never silent. |
| **Q4** | May `/api/status` reassign an existing `UserShip` to a different player or shard? | A gameplay/data-integrity call. Four tests assert it; `/api/travel` forbids the identical case. | **Keep the transfer** (ship resale is plausible in this game) **but make it explicit**: log `event=user_ship_reparented` with both user ids, surface it in admin diagnostics, and refuse while the ship has an active travel. Then make `/api/travel` agree, so one policy governs the rows. |
| **Q5** | Integer or fractional seconds for `_at_unix`? | A client-contract choice. | **Integer.** The fastest clock in the system is a 15-second tick; fractional precision would be false precision, and integers avoid JS float issues. |
| **Q6** | Can the external StarBitizen client tolerate new response keys, and does it special-case `ship.time_remaining == 0`? | The client is outside this repository (U-01, U-02). This gates the F-13 fix. | Confirm before shipping M4's F-13 change. The additive `arrival_at_unix`, `location_resolution` and `warnings` keys are safe either way; the paused-countdown correction is not. |
| **Q7** | Should the 15 000-credit auto-grant stay? | It is a gameplay rule, not a defect, even though its placement in the status read path is. | **Move it to `ShardUser` creation only.** Flagging it because players at zero balance currently receive a refund on every status call, and removing that is player-visible. |

---

## 15. Follow-up playbook readiness

### 15.1 Sufficiently understood to implement now

* **Objective 4 (Jump).** Root cause confirmed at the line level, with the repository's own tests as evidence (`gate_travel_controller_test.rb:179-194`). The fix is three lines in `GateTravelService#create_gate_travel!` plus a nil guard, and the regression test (R-1) is already written out in §12.4. The only open item is Q2, which affects the *second* half of the fix, not the first.
* **Objective 2 (Admin UI).** Every limitation is confirmed against the view and controller; the data all exists; the token set, section layout, fallback labels, timestamp labelling, and the three N+1 traps are specified to the point where an implementation agent needs no further design decisions (§5.3, §5.4). The one honest limitation — that *last successful sync*, *last location update*, and *location source* do not exist as data — is stated, with M5 as the minimal additive instrumentation.
* **Objective 1 (status), mechanism.** All four hard-fail paths are confirmed at the line level with existing tests as corroboration. The repair shape (degrade instead of abort, normalize shard identity, single location writer) is clear. What is *not* settled is policy, not mechanism — Q1, Q3, Q4.
* **Objective 3, inventory and convention.** The inventory is complete, the tick/duration/instant/sim-second axes are cleanly separated, the convention is specified with a naming rule, and the compatibility assessment shows every change is additive except one.

### 15.2 Must be decided before implementation

* **Q1** — the in-flight client-location policy. This is the keystone of M3 and shapes the arrival guard.
* **Q2** — whether a Jump may teleport the ship to a named gateway. Gates the second half of M2 and the fate of four committed tests.
* **Q3** — whether status may keep creating shards. Gates the F-04 repair.
* **Q4** — the `UserShip` ownership policy. Gates reconciling two endpoints that currently contradict each other.
* **Q6** — external client tolerance for the paused-countdown correction. Gates one part of M4.
* **Q7** — the 15 000-credit grant. Gates one part of M6.

Q5 and all six **D** decisions need no owner input; proceed on the recommendations.

### 15.3 Evidence still missing

| Gap | Impact | How to close |
|---|---|---|
| **No test was executed.** `bin/codex_db_doctor` reports `fe_sendauth: no password supplied` for this session's PostgreSQL socket, and I did not reuse credentials found in other local profiles. | Every behavioural claim rests on source reading, committed test assertions, `git` history, and the one DB-free probe in §6.3. The six predicted-failure reproductions in §12.4 are predictions. | **First action of M1**: provision test-database access (the README documents both the railpress/peer path and the limited-role path) and run `bin/codex_test` to establish a green baseline, then add R-1 and R-2 and confirm they fail as predicted. |
| Production state: `last_location` representations and key sets, case-variant shards, unresolvable ship locations, divergence counts (P-02 … P-05, U-04, U-05). | Determines backfill scope and migration safety. | the read-only audit in M1 and the queries in §12.4 R-7. |
| Which failure path is actually firing in production (P-01). | Determines whether F-18 or F-04 is the headline fix. | count `[TradeService.status] location_update failed` log lines and `/api/status` 400/422 rates; the logging already exists at `trade_service.rb:234`. |
| The external StarBitizen client's request payload and response-key dependencies (U-01, U-02). | Gates Q6 and any non-additive change. | owner, or capture anonymized request/response pairs. |
| Tick-chain stall frequency (U-03). | Calibrates how much to trust `arrival_at_unix`. | `TickControl.failure_count`, `last_recovered_at`. |

### 15.4 Recommended first implementation milestone

**M1 — Observability and audit (read-only).**

It is the right first step for four reasons rather than one. It delivers objective 2 in full, with no schema change and no behavioural risk. It converts five Probable findings into measurements, which determines the scope of M3's normalization and M5's backfill. It is the instrument that proves M2's and M3's repairs actually worked in production — without the divergence count, the Jump fix can only be verified in tests. And it forces the test-database access problem to be solved before any behavioural change is attempted.

If the owner would rather fix a defect first, **M2's player-location write alone** (`user_ship.shard_user&.update_current_location!(origin_location)` inside the existing transaction, plus the `ShipAvailability` nil guard) is a three-line, purely additive change that closes the most severe finding in this report, needs no owner decision, and is independently verifiable by R-1. It does not fix the F-02 teleport, but it is a safe, high-value first commit.

### 15.5 Verdict

# CONDITIONAL

The project is ready for a multi-milestone execution playbook, with two conditions:

1. **Answer Q1, Q2, Q3 and Q4 before M2 and M3 are written in detail.** Each is a product decision about gameplay authority that determines what the code should do, not how to do it. M1 can be written and executed without any of them.
2. **Establish a working test database and a green `bin/codex_test` baseline as the first task of M1.** The analysis in this document is from source, committed test assertions, git history, and one database-free probe; no test was run. The playbook should treat the six reproductions in §12.4 as predictions to be confirmed, not as results.

Neither condition blocks writing the playbook. Objectives 2 and 4 can be specified to implementation detail immediately. Objective 1 can be specified as soon as Q1 and Q3 are answered. Objective 3 is fully specified and additive, and should be sequenced last so a timestamp refactor never delays a location repair.

---

*Prepared by Claude Code, 15 November 2026. Discovery only: no application code, schema, data, or deployment was modified. The sole write to this repository is this file. A scratch `.env.codex` created while attempting to provision an isolated test database was removed; `git status` is clean apart from this document.*
