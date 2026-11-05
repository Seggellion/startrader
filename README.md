# 🚀 **Star Bitizen Trade Game API**

An API-only **Ruby on Rails 8** application for a **text-based space trading game** in **Star Bitizen**, played through **Twitch chat**. This API manages **player interactions**, **trade mechanics**, **planetary economy**, and **resource management** through a **tick-based system**.

---

## 📚 **Project Overview**

The **Star Bitizen Trade Game API** facilitates a **text-based space trading game** where:
- Players interact through **Twitch chat commands**.
- The API handles **trade mechanics**, **travel**, **buying/selling commodities**, and **resource generation/consumption**.
- **Planetary outposts** have production facilities to generate resources.
- The system incorporates a **"tick"** to process game actions and update the economy.

**Important:** The **Twitch API integration** is managed externally. This API only handles **game logic** and **data processing**.

---

## 🛠️ **Tech Stack**
- **Backend:** Ruby on Rails 8
- **Database:** PostgreSQL
- **Background Jobs:** Active Job with Delayed Job
- **Testing:** Minitest
- **Task Recovery:** Delayed Job self-chaining plus the tick watchdog rake task

---

## 🚦 **Core Features**
- **Player Management:** Track player data, credits, inventory, and location.
- **Dynamic Economy:** Fluctuating commodity prices based on supply/demand.
- **Trade System:** Buy and sell resources at planetary outposts.
- **Travel Mechanics:** Calculate travel time based on planetary alignments.
- **Production Facilities:** Generate and consume resources using a "tick" system.
- **Resource Consumption:** Automatically adjust supply and demand through periodic ticks.

---

## Tick Operations

The production Procfile must keep both dynos running:

```bash
web: bundle exec rails server -p $PORT
worker: bundle exec rake jobs:work
```

The tick loop is controlled through `TickControl`, runs through `TickJob`, and is repaired by `TickWatchdogJob`. The watchdog is safe to run periodically from Heroku Scheduler:

```bash
bundle exec rake tick:ensure
```

Manual controls:

```bash
bundle exec rake tick:start
bundle exec rake tick:stop
bundle exec rake tick:health
```

Optional boot recovery can be enabled with:

```bash
TICK_BOOTSTRAP=true
```

The tick runner uses PostgreSQL advisory locks so duplicate queued jobs or multiple worker dynos do not process the same tick concurrently.

---

## RabbitMQ Environments

StarTrader publishes `ShipArrival` events to two independent RabbitMQ brokers,
selected per travel:

```text
prod -> production broker
dev  -> development broker
```

A travel picks its broker when it starts, using a query-string parameter on the
travel request:

```text
POST /api/travel?rabbitmq=prod
POST /api/travel?rabbitmq=dev
```

The value is stored on the `ship_travels.rabbitmq_environment` column and is
used later, when the arrival is actually published. Omitting the parameter means
`prod`, so existing callers are unchanged. Any other value returns `422`.

Everything outside the ShipTravel workflow (for example the streamer
`CheckStatus` event) always publishes to production.

## Jump request safety

`POST /api/gate_travel?rabbitmq=prod|dev` now uses the same explicit broker selector
as ordinary travel; invalid values return 422 before
lifecycle work. A top-level JSON `rabbitmq` key also works. The selected broker is
saved on the journey, returned in the response, and bound to its request identity.
For a new request without a selector, an explicit text setting
`gate_rabbitmq_default_shard_<shard_id>` may select `prod` or `dev`; otherwise the
default is production. A retry without a selector inherits its original receipt
broker, even if the shard default has since changed. Explicit request selectors
always win. An invalid configured default blocks new unqualified jumps instead of
falling back silently. This setting never rewrites saved trips or queued messages.
The `rabbitmq_source` response field identifies request, receipt, shard_default,
or global_default selection.
Retry with the same environment and `travel_guid`; saved older receipts retain
their original route.

After a completed jump, an unqualified new jump at that saved arrival gateway
returns 422 `jump_destination_required` rather than silently reversing the trip.
For a deliberate new leg, supply `gateway_name` (the departure gateway in the
current system), or `expected_origin_location` / `expected_destination_location`
using the full canonical names from the response. Direction aliases
`destination_gateway`, `destination`, `to_gateway`, and `to_location` still select
a gateway. `from_location` and `origin_location` alias the origin precondition.
Gateway selection uses named matches; fuzzy matching cannot substitute a different
gateway. Existing remote gateway selection remains available.

Example: from `Stanton Gateway (Pyro)`, select `gateway_name=Stanton Gateway` to
reach `Pyro Gateway (Stanton)`. A deliberate return selects
`gateway_name=Pyro Gateway`. Repeating a failed or uncertain command must keep the
original `travel_guid`, rather than create a new leg.

Gate responses expose canonical `current_location`, `player_location`,
`current_star_system`, and `ship_status` alongside the saved route. Completed
replays return `lifecycle_status=completed`, zero `time_remaining`, and a completed
message. The saved route describes the original trip; `current_location` describes
the ship now, even when replaying an older trip. Status responses also keep a root
`current_location` after server travel completes.

Operational logs correlate `gate_request_accepted`, `gate_request_replayed`,
`gate_request_blocked`, `travel_completed`, and `arrival_published` by request,
ship, receipt and event IDs. Success traces are emitted after the outer transaction
commits. Publisher confirmation still requires a matching consumer trace to prove
that the external bot applied the arrival. These changes do not resume paused
journeys or reconcile existing ship/player discrepancies.

### Required Railpress settings

Create these under **Admin → Settings** as `text` settings. Each key falls back
to the matching environment variable, then to the default.

| Purpose | Setting key | ENV fallback | Default |
| --- | --- | --- | --- |
| Production host | `rabbitmq_host` | `RABBITMQ_HOST` | `localhost` |
| Production username | `rabbitmq_username` | `RABBITMQ_USERNAME` | `guest` |
| Production password | `rabbitmq_password` | `RABBITMQ_PASSWORD` | `guest` |
| Development host | `rabbitmq_dev_host` | `RABBITMQ_DEV_HOST` | *none, required* |
| Development username | `rabbitmq_dev_username` | `RABBITMQ_DEV_USERNAME` | `guest` |
| Development password | `rabbitmq_dev_password` | `RABBITMQ_DEV_PASSWORD` | `guest` |

The development host has no default on purpose. Until `rabbitmq_dev_host` (or
`RABBITMQ_DEV_HOST`) is set, `rabbitmq=dev` arrivals raise a clear
"not configured" error rather than quietly connecting to whatever is listening
locally. Nothing ever falls back from `dev` to `prod` or from `prod` to `dev`.

Store credentials only in Railpress settings or environment variables; never in
source, migrations, seeds, or fixtures.

---

## Local Codex Verification

Run the local verification path with:

```bash
bin/codex_test
```

Codex should use `bin/codex_test` for verification, not raw `bin/rails test`. The helper is self-contained for non-interactive WSL: it prepends rbenv, forces the Ruby pinned by `.ruby-version` and `Gemfile`, prints Ruby diagnostics, then runs Bundler and Rails through that Ruby.

To run targeted tests through the same Ruby launcher:

```bash
bin/codex_test test/controllers/api/ship_travel_controller_test.rb test/models/user_ship_test.rb
```

For lower-level commands, wrap them with:

```bash
bin/codex_exec bundle exec rails test test/models/user_ship_test.rb
bin/codex_exec --ruby-diagnostics
```

The script checks the pinned Ruby version, Bundler, the current Linux user and groups, PostgreSQL reachability, test database preparation, and the Rails test suite.

This app pins Ruby `3.2.2` in `Gemfile` and `.ruby-version`. If your shell is not initialized with that Ruby, `bin/codex_test` will use `rbenv exec` when rbenv is available.

Development and test database configuration defaults to local PostgreSQL through libpq defaults: Unix socket, current PostgreSQL role, and the `star_trader_test` database for tests. If your local PostgreSQL setup requires the `railpress` Linux group, add the Codex/Linux user to that group:

```bash
sudo usermod -aG railpress <linux_user>
```

Restart the WSL session after changing group membership, or run:

```bash
newgrp railpress
```

Diagnose the database path without running the full test suite:

```bash
bin/codex_db_doctor
```

If `bin/codex_db_doctor` reports `fe_sendauth: no password supplied` while `POSTGRES_HOST`, `PGHOST`, and `DATABASE_URL` are unset, Rails is already using the Unix socket path and local PostgreSQL is requiring password auth for that socket connection. Fix that with either the railpress/peer rule in local PostgreSQL, or use the limited Codex role below.

For Codex sessions that should not depend on a personal local PostgreSQL role, create a limited test-only PostgreSQL role and copy `.env.codex.example` to `.env.codex`. Use either `DATABASE_URL` or `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`, and `POSTGRES_TEST_DB`. Do not grant that role access to production data.

One safe local role setup is:

```bash
sudo -u postgres createuser --pwprompt startrader_codex
sudo -u postgres createdb -O startrader_codex star_trader_test
```

If the database already exists, grant ownership or privileges only for the test database before running `bin/codex_test`:

```bash
sudo -u postgres psql -c "ALTER DATABASE star_trader_test OWNER TO startrader_codex;"
```

Inspect the current local roles and test database with:

```bash
sudo -u postgres psql -c "\du"
sudo -u postgres psql -c "\l star_trader_test"
```

Then create `.env.codex` locally:

```bash
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=startrader_codex
POSTGRES_PASSWORD=<local_only_password>
POSTGRES_TEST_DB=star_trader_test
```

---

## 🧑‍💻 **Getting Started**

### **Prerequisites**
- Ruby (3.2.0 or later)
- Rails 8
- PostgreSQL
- Redis (for Sidekiq)
- Yarn & Node.js (for Rails 8 assets)

### **Installation Steps**

1. **Clone the Repository**
```bash
git clone https://github.com/YOUR_USERNAME/star-citizen-trade-game-api.git
cd star-citizen-trade-game-api
