# Decision register — status / location / time repair

Status values: **PENDING** (no owner answer recorded) · **APPROVED** · **REJECTED** · **DEFAULT** (pre-authorized by the playbook).
Owner answers recorded 2026-11-16 (UTC) in the Claude Code session: P0, P1, P2 and Q1 during M00; Q2, Q3, Q4 and Q6 after M01. Every decision that gates a milestone is now recorded.

## Operational decisions raised in M00

| ID | Question | Recommendation | Status |
|---|---|---|---|
| **P0** | Integration base. Production (v178, `c73b582`) and GitHub `main` (`4f42a56`) have diverged. Build on which line, and how should `main` be reconciled at release? | Build on `c73b582`, as the task branch already is. At M08, merge `origin/main` into the release candidate to bring in `61331ac`/`5576bb0`, test it, then fast-forward GitHub `main` to the release commit and push that SHA to Heroku. Exclude the two unreleased branches on top of v178 (`claude/interdiction-hold-release-prod`, `claude/interdict-endpoint-containment`) unless you say otherwise. Leave the main checkout's branch and dirty files alone. Integrate through a fresh `main` checkout/worktree instead (needs your OK). | APPROVED 2026-11-16 — production line + merge `origin/main` at release; interdiction branches excluded |
| **P1** | Which isolated test database may be used? | Either (a) authorize reuse of the existing limited loopback profile `.env.terminal-test` (used by the v172–v177 repairs), or (b) provide a new `.env.codex` per the README's limited-role recipe. | APPROVED 2026-11-16 — reuse `.env.terminal-test` (loopback, `star_trader_terminal_test`), referenced via `CODEX_ENV_FILE`, never copied |
| **P2** | May read-only production database audits run (aggregate counts only, no identifiers kept)? | Yes, via the reviewed `docs/discovery/read_only_travel_audit.rb` pattern plus the M01 audit task, through a read-only transaction. | APPROVED 2026-11-16 — read-only, aggregate counts only, no identifiers retained |

## Product decisions (playbook §1)

| ID | Question | Context found in M00 | Recommendation | Status |
|---|---|---|---|---|
| **Q1** | Status location during travel / after travel | **v173 (owner-authorized 2026-11-03) already decided this more strictly.** Once a ship or player has *any* journey or receipt, client status location is ignored **permanently**, not only while in flight. That is very likely why status "stopped updating `last_location`" (finding N-01). | Narrow v173's rule. Ignore client location while an **unfinished** (active or interdicted) journey exists. Once journeys are finished, idle `*status` updates apply again. Keep the `stale_location` report for in-flight conflicts. **This reverses part of an earlier owner decision, so it needs your explicit answer.** | APPROVED 2026-11-16 — ignore client location only while an unfinished (active or interdicted) journey exists; idle status updates apply after journeys finish; keep `stale_location` for in-flight conflicts (narrows v173). **Refined 2026-11-16 (Q1 follow-up, owner):** also ignore, for 40 ticks (~10 min) after a journey completes, an idle report naming that just-completed journey's origin. This keeps v173's Ac3 protection against stale reverts. Ships with travel history still refuse identity reassignment (Q4). |
| **Q2** | May Jump name a remote gateway (ship moved there instantly)? | v175 *deliberately kept* "remote named gateway selection". Since v172 the player moves with the ship, so it is now an aligned teleport, not a desync. The live bot sends bare jumps (no gateway name). | Reject when the named gateway is not the ship's current location (playbook default). Low client risk, since the bot sends no gateway. Requires revising the teleport tests. | APPROVED 2026-11-16 — reject: a named gateway must be the ship's actual current location, otherwise 422 with no side effects. Bare jumps are unaffected. The teleport tests are rewritten intentionally. |
| **Q3** | Unknown `shard_uuid` | unchanged since discovery | Normalized lookup, creation guarded for uniqueness, `shard_created` warning. Run a duplicate audit (P2) before any unique index. | APPROVED 2026-11-16 — **refuse unknown shards** (owner chose this over the recommendation). `/api/status` must not create a `Shard`, matching `/api/travel`; shards are created by an admin only. Implementation note: the lookup is case/whitespace-normalized, so a case variant of an existing shard is matched rather than refused. Impact: a brand-new live shard gets an error until an admin creates it, and the tests asserting status shard creation are rewritten. |
| **Q4** | Status reparenting of an existing ship | v173 already refuses it for ships with travel history (`status_identity_conflict`); ships without history can still be reparented | Fail closed for all ships unless there is an explicit, audited transfer workflow | APPROVED 2026-11-16 — **allow, audited** (owner chose this over the playbook's fail-closed default). Ships with no travel history may still be reassigned by status, but every reassignment is logged (`event=user_ship_reparented`, both user ids, no secrets) and reported in the response warnings and admin diagnostics. Ships with travel history keep v173's refusal (`status_identity_conflict`). Justification: explicit owner choice; plausible hull resale and re-registration. |
| **Q5** | Epoch precision | — | Integer seconds | DEFAULT |
| **Q6** | External client compatibility | Bot Jump = `ship_guid` + auth only, no `travel_guid`. Requiring it broke travel at v175, restored at v177. Bot source unavailable. | Never require `travel_guid`. Make all response changes additive. Keep legacy `ship.time_remaining` unchanged and add a separate paused-aware key, unless you can confirm the bot tolerates the change. | APPROVED 2026-11-16 — additive only. `ship.time_remaining` stays byte-identical; a new paused-aware key plus `arrival_at_unix` are added. Never require `travel_guid` (confirmed bot contract: bare jumps). |
| **Q7** | 15 000-credit grant | out of scope | Leave unchanged | DEFAULT (deferred) |

Defaults D1–D6 from the discovery apply as written in the playbook.

## Security containment decisions (M06), owner answers 2026-11-16

| ID | Finding | Decision | Status |
|---|---|---|---|
| **S1** | F-10: `POST /api/increment_tick` unauthenticated; `POST /api/set_tick` crashes | Keep both routes but require `X-Secret-Guid`; unauthenticated calls get 401 and never touch the tick; `set_tick` returns 501 instead of crashing. Tick mechanics unchanged. | APPROVED |
| **S2** | F-11: `GET/POST /users` unauthenticated; two dead `minecraft_uuid` routes | Admin-only `/users` JSON routes; remove the two dead member routes | APPROVED |
| **S3** | F-23: routed `MovesController#create` with a live `byebug` | Remove the route and action; move the `byebug` gem to `:development, :test`; leave `.byebug_history` untouched | APPROVED |

## Release decisions (M08/M09), owner answers 2026-11-16

| ID | Decision | Status |
|---|---|---|
| **R1** | GO: deploy RC `3d7e1dc` to Heroku `star-trader` (v179) using the maintenance sequence. No staging app exists; alternative qualification is the green merged suite, migration rehearsals and race tests. | APPROVED |
| **R2** | Backup verification by `pg:backups:capture` plus Heroku Completed status (no download of production data) | APPROVED |
| **R3** | Production smoke is read-only only (no test identity, no status/Jump writes) | APPROVED |
| **R4** | Proceed despite the pre-existing prod RabbitMQ outage (no prod deliveries since 2026-11-05 15:14 UTC); treat it as a baseline, not a rollback trigger; owner follow-up | APPROVED |

## Closeout decisions (M10), owner answers 2026-11-16

| ID | Decision | Status |
|---|---|---|
| **C1** | Land the closeout evidence on `main` as a **documented docs-only exception**: GitHub/local `main` advance to documentation-only commit(s) after the deployed `3d7e1dc`, whose runtime tree is identical (verified `git diff --name-only 3d7e1dc <closeout>` lists only `docs/`). **No redeploy**; production stays v179 `3d7e1dc`. | APPROVED |
| **C2** | Do not create a physical main checkout. The `main` branch reference equals GitHub `main`; the canonical checkout `/home/dusti/startrader` stays on `codex/restore-bare-jump` with the owner's uncommitted `config/initializers/cors.rb` change and untracked files untouched. | APPROVED |
