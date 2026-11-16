# M06 — Security and legacy-route containment

**Verdict: PASS (2026-11-16).** Owner decisions S1–S3 (see `DECISIONS.md`). No gameplay, tick mechanics, economy or data were changed.

Pre-change caller inventory: no code, script or documentation in the repository calls `/api/increment_tick`, `/api/set_tick`, `GET/POST /users`, the `minecraft_uuid` routes, or `POST /api/user_ships/:id/move`. The production router log sample (M00) was too short to show external callers, so it is inconclusive. Each change below is safe if an unknown caller exists: an authorized caller keeps working, and a broken route was already broken.

| Finding | Before | After |
|---|---|---|
| **F-10** `POST /api/increment_tick` | **anyone** could advance the entire simulation | `SecretGuidAuth` required (`X-Secret-Guid`, `secret_guid` param, or JSON body, like the other integration endpoints). Unauthenticated → 401 and `Tick.increment!` is never called. With the secret, behavior is unchanged. |
| F-10 `POST /api/set_tick` | crashed (`Tick.set_current` never existed) | auth required, then `501 {"error":"Setting the tick is not supported; use the admin tick controls."}` |
| **F-11** `GET /users`, `GET /users/:id`, `POST /users` | unauthenticated; `render json: User.all` actually **overflowed the stack (500 for every caller)** | signed-in **admin only** (anon 401, player 403). Responses carry only `id, username, uid, twitch_id, provider, user_type, created_at, updated_at`. |
| F-11 dead routes | `edit_minecraft_uuid` / `update_minecraft_uuid` routed to non-existent actions | removed |
| **F-23** `POST /api/user_ships/:id/move` | live `byebug` breakpoint (`byebug` loaded in production), then a `NameError` | route and `MovesController` removed (use `POST /api/travel`); `byebug` moved to `group :development, :test`. `Gemfile.lock` unchanged (Bundler records no groups). **`.byebug_history` left untouched** for owner review. |

Still deferred, not approved: F-07 (JSONB re-encoding), F-08 (the legacy Minecraft `Api::ShardUsersController` coordinate writer; it is dead code behind a Bearer token), F-12 (15 000-credit grant, Q7), F-14 (travel history), F-16 (resolver performance).

## Changed files

`app/controllers/api/tick_controller.rb`, `app/controllers/users_controller.rb`, `config/routes.rb`, `Gemfile`, deleted `app/controllers/moves_controller.rb`. CRLF endings preserved where present. New test `test/controllers/security_containment_test.rb` (5 tests).

## Tests actually run

| Command | Result |
|---|---|
| `bin/codex_test test/controllers/security_containment_test.rb` | **5 runs, 31 assertions, 0 failures**: route/auth matrix, `Tick.increment!` never invoked without auth, no user created by an anonymous POST, routes gone, `byebug` groups |
| `bin/codex_test` (full) | **657 runs, 6749 assertions, 33 failures, 24 errors**: **0 new**, 1 baseline fixed (M04) |

## Release note

Heroku installs gems without `development:test`, so `byebug` will no longer be present in production. Nothing outside the removed controller calls it, and a grep of `app`, `lib` and `config` found no other `byebug` call.

## Rollback

Revert the M06 commit.
