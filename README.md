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

## Local Codex Verification

Run the local verification path with:

```bash
bin/codex_test
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

For Codex sessions that should not depend on a personal local PostgreSQL role, create a limited test-only PostgreSQL role and copy `.env.codex.example` to `.env.codex`. Use either `DATABASE_URL` or `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`, and `POSTGRES_TEST_DB`. Do not grant that role access to production data.

One safe local role shape is:

```sql
CREATE ROLE startrader_codex LOGIN PASSWORD 'change-me';
CREATE DATABASE star_trader_test OWNER startrader_codex;
```

If the database already exists, grant ownership or privileges only for the test database before running `bin/codex_test`.

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
