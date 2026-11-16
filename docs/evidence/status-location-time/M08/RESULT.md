# M08 — Release candidate, nonproduction rehearsal, rollback packet

**Verdict: CONDITIONAL → awaiting owner GO.** The release candidate is fixed and fully green. Production-side G4 items need the owner: there is no staging app, the backup restorability method must be chosen, and the smoke-test scope must be agreed. See `RELEASE_PACKET.md`.

## Integration (decision P0)

* `git fetch origin main` (live `4f42a566b73f…`), then `git merge --no-ff origin/main` into `claude/status-location-time-repair`. The merge commit is `b60e97b`.
* Conflicts and their resolutions:
  * `db/schema.rb`: version marker set to `2026_11_16_020000`.
  * `test/services/trade_service_test.rb`: kept the F-05 username contract over `main`'s RecordInvalid expectation (as predicted in `M04/RESULT.md`).
* Auto-merged files were reviewed: `trade_service.rb` keeps `main`'s `shard_id`-scoped buy/sell lookups *and* the M04 normalized shard matching; `shard_user.rb` has `main`'s `JsonStoreCoder` *and* the M03 location instrumentation. Production features are all present (travel lifecycle, resume interdiction, CORS unchanged versus `c73b582`).
* The merge brings exactly `main`'s `61331ac` and `5576bb0` code: 15 files, +97/−62 lines in app/config/db.
* The response-shape tests were updated to the additive keys. With `main`'s sort fix they now pass.
* Pending from M01: the `JsonStoreCoder` now in the RC resolves latent finding M01-a (native jsonb rows raising on read).

## Tests actually run (merged tree)

| Command | Result |
|---|---|
| `rails db:migrate` (isolated test DB) | applied `20261024170000_widen_cargo_unit_prices` |
| `bin/codex_test` (full) | **675 runs, 7073 assertions, 0 failures, 0 errors, 0 skips** — the first fully green full suite on the release line. `main`'s regression repair cleared all 58 baseline identities, and nothing new fails. |
| `bin/codex_test docs/evidence/status-location-time/M00/repro_test.rb` | 7 runs, 1 failure: **R-6 only, failing by design** (Q6 keeps the legacy `ship.time_remaining`; see M05). R-1, R-2, R-3, R-4, R-5 and N-01 pass. |
| earlier on the same code (M07) | `zeitwerk:check` OK; both new migrations rehearsed down/up with a byte-identical schema |

## Diff review

* No secrets, no `.env*`, no CORS origin change, no tick, speed or orbital setting change, no economy change (Q7 untouched).
* All user-owned and untracked files in the main checkout are untouched. No other worktree was modified.
* Unreleased branches that are deliberately **not** included (P0): `claude/interdiction-hold-release-prod`, `claude/interdict-endpoint-containment`. Also not included: the main checkout's two v177 documentation commits (`313f17a`, `6326f24` on `codex/restore-bare-jump`). They are owner evidence documents, not code, and can be merged separately.

## G4 status

| Requirement | State |
|---|---|
| Release candidate SHA fixed, tests green | ✅ |
| Diff, security and compatibility review | ✅ (packet §"Expected response and behavior changes") |
| Restorable production backup | ⏳ captured at M09 step 1; verification method needs the owner |
| Deploy authority and mechanism verified | ✅ Heroku Git, owner account, v173–v178 precedent |
| Nonproduction qualification | ⚠️ **No StarTrader staging app exists** (`heroku apps`). Alternative evidence: the green merged full suite, migration rehearsals, the multi-connection PostgreSQL race tests, and the read-only production audits. **Needs an owner go/no-go.** |
| Rollback runbook | ✅ `RELEASE_PACKET.md` |
