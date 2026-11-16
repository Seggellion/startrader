# Decision register — status / location / time repair

Status values: **PENDING** (no owner answer recorded) · **APPROVED** · **REJECTED** · **DEFAULT** (pre-authorized by the playbook).
Owner answers recorded 2026-11-16 (UTC) in the Claude Code session for P0, P1, P2 and Q1. Q2–Q4 and Q6 remain pending.

## Operational decisions raised in M00

| ID | Question | Recommendation | Status |
|---|---|---|---|
| **P0** | Integration base. Production (v178, `c73b582`) and GitHub `main` (`4f42a56`) have diverged. Build on which line, and how should `main` be reconciled at release? | Build on `c73b582`, as the task branch already is. At M08, merge `origin/main` into the release candidate to bring in `61331ac`/`5576bb0`, test it, then fast-forward GitHub `main` to the release commit and push that SHA to Heroku. Exclude the two unreleased branches on top of v178 (`claude/interdiction-hold-release-prod`, `claude/interdict-endpoint-containment`) unless you say otherwise. Leave the main checkout's branch and dirty files alone. Integrate through a fresh `main` checkout/worktree instead (needs your OK). | APPROVED 2026-11-16 — production line + merge `origin/main` at release; interdiction branches excluded |
| **P1** | Which isolated test database may be used? | Either (a) authorize reuse of the existing limited loopback profile `.env.terminal-test` (used by the v172–v177 repairs), or (b) provide a new `.env.codex` per the README's limited-role recipe. | APPROVED 2026-11-16 — reuse `.env.terminal-test` (loopback, `star_trader_terminal_test`), referenced via `CODEX_ENV_FILE`, never copied |
| **P2** | May read-only production database audits run (aggregate counts only, no identifiers kept)? | Yes, via the reviewed `docs/discovery/read_only_travel_audit.rb` pattern plus the M01 audit task, through a read-only transaction. | APPROVED 2026-11-16 — read-only, aggregate counts only, no identifiers retained |

## Product decisions (playbook §1)

| ID | Question | Context found in M00 | Recommendation | Status |
|---|---|---|---|---|
| **Q1** | Status location during travel / after travel | **v173 (owner-authorized 2026-11-03) already decided this more strictly.** Once a ship or player has *any* journey or receipt, client status location is ignored **permanently**, not only while in flight. That is very likely why status "stopped updating `last_location`" (finding N-01). | Narrow v173's rule. Ignore client location while an **unfinished** (active or interdicted) journey exists. Once journeys are finished, idle `*status` updates apply again. Keep the `stale_location` report for in-flight conflicts. **This reverses part of an earlier owner decision, so it needs your explicit answer.** | APPROVED 2026-11-16 — ignore client location only while an unfinished (active or interdicted) journey exists; idle status updates apply after journeys finish; keep `stale_location` for in-flight conflicts (narrows v173) |
| **Q2** | May Jump name a remote gateway (ship moved there instantly)? | v175 *deliberately kept* "remote named gateway selection". Since v172 the player moves with the ship, so it is now an aligned teleport, not a desync. The live bot sends bare jumps (no gateway name). | Reject when the named gateway is not the ship's current location (playbook default). Low client risk, since the bot sends no gateway. Requires revising the teleport tests. | PENDING |
| **Q3** | Unknown `shard_uuid` | unchanged since discovery | Normalized lookup, creation guarded for uniqueness, `shard_created` warning. Run a duplicate audit (P2) before any unique index. | PENDING |
| **Q4** | Status reparenting of an existing ship | v173 already refuses it for ships with travel history (`status_identity_conflict`); ships without history can still be reparented | Fail closed for all ships unless there is an explicit, audited transfer workflow | PENDING |
| **Q5** | Epoch precision | — | Integer seconds | DEFAULT |
| **Q6** | External client compatibility | Bot Jump = `ship_guid` + auth only, no `travel_guid`. Requiring it broke travel at v175, restored at v177. Bot source unavailable. | Never require `travel_guid`. Make all response changes additive. Keep legacy `ship.time_remaining` unchanged and add a separate paused-aware key, unless you can confirm the bot tolerates the change. | PENDING (partial evidence) |
| **Q7** | 15 000-credit grant | out of scope | Leave unchanged | DEFAULT (deferred) |

Defaults D1–D6 from the discovery apply as written in the playbook.
