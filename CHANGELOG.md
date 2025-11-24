# CHANGELOG

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
- Renamed `stylesheet_registrymap_tags` to `stylesheet_registry_tags` (old name kept as deprecated alias)
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
