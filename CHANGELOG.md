# CHANGELOG

## 1.0.0 (2025-11-20)

- Initial stable release
- Attribute-based CSS scoping for Phlex components, ViewComponent, and ERB templates
- Component-scoped CSS encapsulation using `[data-capsule="..."]` selectors (combined selector format: `[data-capsule="..."].class`)
- Per-component-type scope IDs (shared across all instances)
- Automatic HTML wrapping with scoped elements
- CSS processor with support for regular selectors, pseudo-classes, `@media` queries, `@keyframes`, and component-scoped `:host` selectors
- Thread-safe stylesheet registry for head injection with namespace support
- Multiple caching strategies: no caching, time-based, custom proc, and file-based caching
- File-based caching with Rails asset pipeline integration and Rake tasks
- Security features: path traversal protection, CSS size limits (1MB), scope ID validation, filename validation
- Ruby >= 3.0 requirement
- Comprehensive test suite with > 93% coverage

