# Engineering and prose audit before 2.0.3 publish

## Participants

Andrei Makarov (@amkisko)

## Decisions

Re-audit main for the unpublished 2.0.3 cut. Include member CssProcessor keyframes and nesting, pending head clear, blank checks, file-cache warn, release gates, pull_request CI, and ASCII docs punctuation. Leave tag and RubyGems publish to make release after commit.

## Effects

Pipeline: render -> CssProcessor -> registry / file writer -> head inject -> HTML. Boundary mode covered Rack buffering and disk writes. Resource and identification modes: no new person identifiers in gem logs. Queue, worker, learned-system, and physical plant modes skipped (absent).

Ranked fixes applied:

1. Unscoped `@keyframes` / `@font-face` / `@property` steps under selector patching (high confidence, observed).
2. Hoist non-nestable at-rules outside nesting wrapper (high confidence, observed).
3. Clear pending request stylesheets when `</head>` is missing (high confidence, observed).
4. Nil/empty checks instead of ActiveSupport `blank?` on core paths (high confidence, observed).
5. Warn once on illegal `:file` cache fallback (high confidence, observed).
6. Changelog heading and confirmation specs; CHANGELOG dated 2026-11-03.
7. ASCII and marketing-tone pass on README, CHANGELOG, gemspec, and docs/non_rails_support.md.

Deferred (documented in the issue): class CSS cache mutex, helper/component dedupe, double `component_styles` eval, file-path cache revalidation, middleware max-bytes.

Checks observed in this session:

- bundle exec rubocop on touched Ruby files: 11 files, no offenses.
- bundle exec rbs validate: ok.
- bundle exec rspec on css_processor, stylesheet_registry, head_injection_middleware, component, view_component, release_version_check: 249 examples, 0 failures.
- bundle exec polyrun parallel-rspec --workers 5 --merge-failures: exit 0; coverage/merged-summary.txt 97.00% lines (1101 / 1135) across 19 files.
- gem build style_capsule.gemspec and Gem::Package#verify for 2.0.3: ok.

## Next

Commit, then make release.

## Source

- docs/issues/20261103150931_engineering-prose-release-audit.md
- CHANGELOG.md section 2.0.3 (2026-11-03)
