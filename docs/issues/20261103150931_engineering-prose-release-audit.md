# Engineering and prose audit before 2.0.3 publish

## Participants

Andrei Makarov (@amkisko)

## Decisions

Re-audit main for the unpublished 2.0.3 cut after the 2026-10-28 release-tooling pass. Include CssProcessor keyframes and nesting hoist, pending head clear when `</head>` is missing, ActiveSupport-free blank checks, `:file` cache fallback warning, release confirmation and changelog gates, pull_request CI, and ASCII docs punctuation. Leave tag and RubyGems publish to `make release` after commit.

## Effects

Pipeline: component/helper render -> CssProcessor -> StylesheetRegistry / CssFileWriter -> HeadInjectionMiddleware -> HTML. Boundary mode covered Rack body buffering and filesystem writes. Resource and identification modes: no new person identifiers in gem logs; cold-require numbers stay session observations. Queue, worker, learned-system, and physical plant modes skipped (absent).

Ranked fixes applied:

1. Skip selector patching inside `@keyframes` / `@font-face` / `@property` (high confidence, observed; prior keyframes example was futile).
2. Hoist non-nestable at-rules outside the nesting wrapper (high confidence, observed).
3. Clear pending request stylesheets when inject cannot find `</head>` or tags are empty (high confidence, observed).
4. Replace `blank?` with nil/empty checks in CssProcessor and HeadInjectionMiddleware (high confidence, observed).
5. Warn once when `:file` falls back to `:none` without class-method `component_styles` (high confidence, observed).
6. Changelog heading and confirmation specs; CHANGELOG dated 2026-11-03; prose pass on README, gemspec, docs/non_rails_support.md, and builder skip warn punctuation.

Deferred:

- Class-level CSS cache mutex under threaded hosts.
- Deduping Phlex / ViewComponent / helper render paths and stylesheet_registry split.
- `component_styles` double evaluation per render.
- CssFileWriter positive-path cache revalidation after external delete.
- Optional max-bytes skip for middleware buffering.

## Next

Commit, then `make release`.

## Source

- docs/reviews/20261103150931_engineering-prose-release-audit.md
- CHANGELOG.md section 2.0.3 (2026-11-03)
- Prior pass: docs/reviews/20261028_engineering-audit-release-preparation.md
