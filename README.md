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
- **Backend:** Ruby on Rails 8 (API-only mode)
- **Database:** PostgreSQL
- **Background Jobs:** Sidekiq with Redis
- **Testing:** RSpec
- **Task Scheduling:** Cron or Sidekiq Scheduler

---

## 🚦 **Core Features**
- **Player Management:** Track player data, credits, inventory, and location.
- **Dynamic Economy:** Fluctuating commodity prices based on supply/demand.
- **Trade System:** Buy and sell resources at planetary outposts.
- **Travel Mechanics:** Calculate travel time based on planetary alignments.
- **Production Facilities:** Generate and consume resources using a "tick" system.
- **Resource Consumption:** Automatically adjust supply and demand through periodic ticks.

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
