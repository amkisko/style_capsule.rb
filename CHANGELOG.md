# CHANGELOG

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

