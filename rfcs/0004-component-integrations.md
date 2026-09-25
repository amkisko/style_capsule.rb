# RFC 0004: Component integrations

- Feature Name: component-integrations
- Type: Standards Track
- Status: Stable
- Created: 2026-09-25
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0003, RFC 0005, RFC 0006

## Summary

Expose one configuration surface (`style_capsule`) and three integration paths: Phlex (`StyleCapsule::Component`), ViewComponent (`StyleCapsule::ViewComponent`), and ERB / standalone helpers. Components supply CSS via `component_styles` (or helper arguments). Render wraps markup and scopes CSS per RFC 0003.

## Motivation

Hosts write components in more than one template system. Separate DSLs for Phlex, ViewComponent, and ERB would diverge. A single class method that sets namespace, cache strategy, scoping strategy, head rendering, and wrapper tag keeps inheritance hierarchical and reduces deprecated entry points.

## Guide-level explanation

Phlex: include `StyleCapsule::Component`, call `style_capsule(...)`, define `component_styles`, render as usual. ViewComponent: include `StyleCapsule::ViewComponent`, same DSL, implement `call`. ERB: `<%= style_capsule do %>...<style>...</style>...<% end %>`. Optional `tag:` chooses the wrapper element (default `:div`). Call `clear_css_cache` on the class after changing strategy in development.

Helper modules `StyleCapsule::PhlexHelper`, `StyleCapsule::ViewComponentHelper`, and the Rails / standalone helpers expose `register_stylesheet` and `stylesheet_registry_tags` (RFC 0005).

## Reference-level explanation

`style_capsule` configures optional `namespace`, `cache_strategy`, `cache_ttl`, `cache_proc`, `scoping_strategy`, `head_rendering`, and `tag`. Capsule id defaults to a hash of the component class name and is shared across instances. Hosts MAY set `capsule_id` for tests. Instance or class `component_styles` supply CSS; file cache strategy requires class-method styles (RFC 0006). Class-level scoped CSS cache is bounded (`MAX_CSS_CACHE_ENTRIES` = 256). Rails railtie loads helpers; without Rails, `StandaloneHelper` and `CssProcessor` remain usable.

Missing styles yield unscoped markup wrapping only when the integration still wraps; empty CSS is a no-op for the processor (RFC 0003).

## Registrar

Public modules: `StyleCapsule::Component`, `StyleCapsule::ViewComponent`, `StyleCapsule::Helper`, `StyleCapsule::StandaloneHelper`, `StyleCapsule::PhlexHelper`, `StyleCapsule::ViewComponentHelper`. Public methods: `style_capsule`, `component_styles`, `clear_css_cache`, `capsule_id`, `scope_css`.

## Drawbacks

Three include paths still exist because the host frameworks differ. Class-level CSS cache eviction is LRU-ish by insertion order and can reprocess under churn.

## Rationale and alternatives

One DSL (`style_capsule`) replaced earlier split methods such as `head_rendering!`. Framework-specific only adapters would duplicate scoping and registry wiring. Doing nothing leaves hosts copying attribute wrappers by hand.

## Prior art

Phlex and ViewComponent component bases; Rails view helpers; Vue/Svelte scoped style blocks colocated with templates.

## Unresolved questions

Whether `stylesheet_registry` as a separate class method remains documented beside `style_capsule`, or becomes private once all hosts migrate.
