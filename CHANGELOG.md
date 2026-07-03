# CHANGELOG

## Unreleased

## 2.0.1 (2026-07-03)

- Fix `render_head_stylesheets` clearing request-scoped registrations added after a template pre-render but before layout head (Phlex + Rails layout capture)
  - Only remove request-scoped entries that existed when head rendering started; later body registrations remain for `HeadInjectionMiddleware`
- Document Phlex + Rails layout pattern: when `HeadInjectionMiddleware` is enabled, omit `stylesheet_registry_tags` for request-scoped namespaces and let the middleware inject all pending styles before `</head>` (calling `render_head_stylesheets` in layout head clears pre-captured template registrations without reliably writing tags into the Phlex buffer)

## 2.0.0 (2026-07-03)

- BREAKING: split `StylesheetRegistry.register` into request-scoped `register` and boot-time `register_eager`
  - Replace boot-time `StylesheetRegistry.register(...)` with `register_eager(...)`; keep `register` for render-time / `register_stylesheet` paths
- BREAKING: enable `StyleCapsule::HeadInjectionMiddleware` by default (`config.style_capsule.head_injection_middleware`); set to `false` to disable
- Fix render-time `register_stylesheet` missing from `<head>` on the same request when layouts render head before body
- Add `HeadInjectionMiddleware` to inject pending stylesheet tags before `</head>` after the response body is rendered
  - Skips chunked responses and only buffers when pending request-scoped stylesheets exist; accepts any 2xx HTML response
- Dedupe eager manifest and request-scoped file paths by logical path when rendering `<head>` (request registration wins on option conflicts)
- Bound class-level component CSS cache (`MAX_CSS_CACHE_ENTRIES` = 256)
- Single-pass `<style>` extraction in ERB / standalone helpers (`StringScanner`)
- Reject parent path segments (`..`) in `AssetPath.validate_logical_path!`
- Add `StyleCapsule::StylesheetRegistry.inject_pending_head_stylesheets` for manual/testing use
- Extract shared Phlex / ViewComponent class DSL into `StyleCapsule::ComponentClassMethods`
- Fix class-level `scope_css` cache keys to include a CSS fingerprint (instance methods returning different styles per render)
- Fix ERB / standalone `Helper#scope_css` thread cache keys to include a CSS fingerprint
- Add `tag:` option to `StandaloneHelper#style_capsule` (aligned with the Rails helper)
- Fix `PhlexHelper#stylesheet_registry_tags` to always return a string when `safe` is unavailable
- Pass `component_class:` into `CssProcessor` from `ViewComponent` for consistent instrumentation
- Defer `input_size` in `Instrumentation.instrument_css_processing` until instrumentation runs
- Documentation: add [docs/non_rails_support.md](docs/non_rails_support.md); document late head injection, `register_eager`, streaming / Live caveats
- RBS: `StylesheetRegistry` no longer declared as a subclass of `ActiveSupport::CurrentAttributes` only

## 1.4.0 (2025-11-26)

- Added unified `style_capsule` class method for configuring all StyleCapsule settings (namespace, cache strategy, CSS scoping, head rendering) in a single call
- Added automatic namespace fallback in `register_stylesheet` helper methods - when namespace is not specified, uses the component's configured namespace from `style_capsule`
- Removed deprecated `head_rendering!` method (use `style_capsule` instead)
- Removed deprecated `stylesheet_registrymap_tags` alias (use `stylesheet_registry_tags` instead)
- Refactored namespace configuration to use instance variables instead of constants for better inheritance behavior

## 1.3.0 (2025-11-26)

- Added comprehensive instrumentation via `StyleCapsule::Instrumentation` using ActiveSupport::Notifications
- Instrumentation events for CSS processing (`style_capsule.css_processor.scope`) with duration and size metrics
- Instrumentation events for CSS file writing (`style_capsule.css_file_writer.write`) with duration and size metrics
- Added fallback directory support for CSS file writing when default location is read-only (e.g., Docker containers)
- Automatic fallback to `/tmp/style_capsule` when primary output directory is not writable
- Instrumentation events for fallback scenarios (`style_capsule.css_file_writer.fallback`, `style_capsule.css_file_writer.fallback_failure`)
- Instrumentation events for write failures (`style_capsule.css_file_writer.write_failure`)
- All instrumentation is zero-overhead when no subscribers are present (only calculates metrics when actively monitored)
- Improved test coverage reporting and analysis tools
- Added community guidelines and governance documents

## 1.2.0 (2025-11-24)

- Added `StyleCapsule::ClassRegistry` for Rails-friendly class tracking without ObjectSpace iteration
- Fixed development environment bug where `ObjectSpace.each_object(Class)` could trigger errors with gems that override `Class#name` (e.g., Faker)
- Improved `ComponentBuilder` to use ClassRegistry first, with ObjectSpace fallback for compatibility
- Classes are now automatically registered when including `StyleCapsule::Component` or `StyleCapsule::ViewComponent`
- Better performance in development mode by tracking only relevant classes instead of iterating all classes
- Enhanced error handling for classes that cause issues during iteration

## 1.1.0 (2025-11-21)

- Made Rails dependencies optional: `railties` and `activesupport` moved to development dependencies
- Core functionality now works without Rails (Sinatra, Hanami, plain Ruby, etc.)
- Rails integration remains fully supported via Railtie
- Added `StyleCapsule::StandaloneHelper` for non-Rails frameworks
- `StylesheetRegistry` now works without `ActiveSupport::CurrentAttributes` using thread-local storage fallback
- Renamed `stylesheet_registrymap_tags` to `stylesheet_registry_tags` (deprecated alias removed in 1.4.0)
- Extracted CSS building logic from Rake tasks into `StyleCapsule::ComponentBuilder`
- Fixed XSS vulnerability in `escape_html_attr` by using `CGI.escapeHTML` for proper HTML entity escaping
- Optimized ActiveSupport require to avoid exception handling overhead in Rails apps

## 1.0.2 (2025-11-21)

- Fix default output directory for CSS files to app/assets/builds/capsules/

## 1.0.1 (2025-11-21)

- Update ViewComponent dependency to version 4.0 and adjust compatibility in tests
- Enhance error handling in style_capsule Rake task for ViewComponent loading issues
- Remove Rails 6 support from Appraisals file and update Rails 7.2 dependencies
- Update Rails and ActiveSupport version requirements
- Add Codecov badge to README

## 1.0.0 (2025-11-20)

- Initial stable release
- Attribute-based CSS scoping for Phlex components, ViewComponent, and ERB templates
- Component-scoped CSS encapsulation using `[data-capsule="..."]` selectors (combined selector format: `[data-capsule="..."].class`)
- Per-component-type scope IDs (shared across all instances)
- Automatic HTML wrapping with scoped elements
- CSS processor with support for regular selectors, pseudo-classes, `@media` queries, `@keyframes`, and component-scoped `:host` selectors
- Thread-safe stylesheet registry for head rendering with namespace support
- Multiple caching strategies: no caching, time-based, custom proc, and file-based caching
- File-based caching with Rails asset pipeline integration and Rake tasks
- Security features: path traversal protection, CSS size limits (1MB), scope ID validation, filename validation
- Ruby >= 3.0 requirement
- Comprehensive test suite with > 93% coverage
