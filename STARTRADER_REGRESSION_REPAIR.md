# Full regression repair

24 October 2026. Source baseline: `3868c01b11ca399acbff77d63b61c9d033bb2157`, following the verified v168 travel release. This follow-up repairs the full regression suite without changing the calibrated orbital or travel timing implementation. No production deployment or production data change is part of this test-repair qualification.

## Reproduced baseline

The required `bin/codex_test` path reproduced **468 tests / 5247 assertions, 34 failures and 26 errors, zero skips**. Tests ran against a verified isolated local PostgreSQL database under a non-superuser role. Real Bunny connections are prohibited. The production database, scheduler and brokers are not test targets.

## Corrections

- Admin import tests now establish a real session through a mocked external OAuth callback. They retain admin authentication and authorization; additional anonymous/player tests prove imports remain blocked. Obsolete generated GET helpers are replaced with actual RESTful admin menu, nested item, dashboard and contact-message requests, with persistence and rendering assertions.
- Menu associations, root queries, forms and browser payloads use the existing `parent_id` column. The list scope uses the supported menu association, the missing new-item form renders, and nested record lookups stay within their menu. Parent validation rejects cycles and cross-menu trees. No menu schema change is needed. The admin layout also stops loading the module entry point a second time as a classic script, eliminating the observed browser syntax error.
- Buy, sell and listing paths share the existing UUID/name shard resolver and use the resolved shard foreign key. This also preserves membership when a shard's display name changes. Unknown shards fail before wallet/cargo changes.
- Commodity responses tolerate missing star/location rows and use resolved system metadata. Existing terminal-side price conventions and location-only labels are preserved: stale expectations are aligned with the repository's intentional July API changes, rather than reversing them. Freshness assertions use the current clock instead of a hardcoded date.
- Shard JSON stores accept both native objects emitted by the duplicate-cleanup migration and older JSON-string representations. The normal serialization format and field values are retained; no bulk data conversion is performed. Both forms and migration merge behavior are exercised.
- Cargo buy/sell unit-price precision increases from decimal(10,2) to decimal(15,2), matching existing catalog/run prices. This fixes the legitimate large-price sale/wallet regression while preserving cents. The new migration tests safe reversal and refuses narrowing when any existing magnitude exceeds the previous range.
- Contact messages remain standalone email submissions. The old callback and contact-user association addressed a nonexistent `users.email` column and attempted to create invalid login accounts. They are removed, as is the same invalid account creation in the public submission controller. Valid/invalid submissions and marking messages read are tested without creating users.
- Broken importer fixtures now genuinely lack matching location context, gateway helpers supply required keywords, and the cleanup test uses the Rails index API correctly. Minitest mock support is loaded explicitly by the shared helper so focused runs do not depend on the travel pipeline test loading first. The unavailable-lock fake is a non-yielding callable: the prior Minitest value stub yielded the protected block despite returning false. Market-price fixtures cross the existing update threshold, with an additional below-threshold test; production volatility settings are unchanged.
- Expected sorted response keys are actually alphabetic. The conflicting-name status test now enforces the explicitly introduced case-insensitive unique-username contract (commit `dab5980`), verifies rejection of the conflicting GUID/name and proves the original user and ship remain untouched. Username uniqueness is not relaxed.

No failed test is skipped or quarantined. The eleven nonexistent public menu scaffolds are replaced with corresponding real admin CRUD tests, and focused regressions increase total coverage.

## Qualification

- Required `bin/codex_test`: **485 tests / 5575 assertions, zero failures/errors/skips**, final seed 271828 (also passed earlier seed 44721).
- Complete `rails test:all` through the pinned Ruby launcher: **485 tests / 5575 assertions, zero failures/errors/skips**, independently randomized seed 49263. This task also runs the required asset build. No populated system-test files are excluded from this result.
- An independent trading-only helper run passes **99 tests / 450 assertions**, proving mock support no longer depends on other test files loading first.
- Separate terminating Rails/Tailwind asset precompile passes. Existing Browserslist freshness warning remains.
- `git diff --check` passes.
- Source comparison with the baseline verifies unchanged orbital engine/catalog/browser modules, `TravelTiming`, Tick/TickJob/TickRunner, TravelService/calculator, gateway service, saved-travel model, arrival processor and deterministic travel pipeline tests. The full green suite includes all orbital/phase/anchor, 1 Gm/tick, 15-second scheduling, minimum/ceiling, saved journey and RabbitMQ routing checks.

Google Chrome qualification is complete against a separate local preview with stopped ticks, fake external authentication and normal CSRF protection, bound to loopback. Login, menu rendering, link creation, parent selection, nested tree rendering and reload persistence pass. The restored standalone new-item form also creates a child under the chosen parent. A fresh tab reports no console errors and no duplicate classic application script include. An earlier extension disconnection was recovered; its incomplete check is superseded by these completed results. No alternate browser was used. The preview is stopped after qualification. A viewport proof is saved locally as `regression-menu-chrome.png`; detailed logs remain in ignored `tmp/` files.

## Schema and rollback

`20261024170000_widen_cargo_unit_prices.rb` changes only the two cargo unit-price column precisions. No orbital, location, tick, travel, wallet or broker schema/data changes are required. It has been applied and reversed in isolated tests only. Before any later production release, apply it through the established migration process after exact app/source/database revalidation. A source rollback can leave the wider compatible columns in place; do not force a narrowing that would reject accepted large prices. The explicit down guard prevents that loss. All anchored orbital phase and saved journey timing remain governed by the existing v3 schedule and v168 policy.
