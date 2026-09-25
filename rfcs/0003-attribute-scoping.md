# RFC 0003: Attribute scoping

- Feature Name: attribute-scoping
- Type: Standards Track
- Status: Stable
- Created: 2026-09-25
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0004

## Summary

Rewrite component CSS so selectors only match under a `data-capsule` attribute. Each component class gets one capsule id shared across instances. Two strategies ship: selector patching (default) and CSS nesting.

## Motivation

Unscoped selectors apply wherever a class name appears. Hosts need a deterministic rewrite that leaves class names unchanged and fails closed on oversized or breakout CSS. Per-instance ids would multiply stylesheets for the same component type. Per-class ids keep cache keys and head registrations stable.

## Guide-level explanation

Call `StyleCapsule::CssProcessor.scope_selectors(css, capsule_id)` for patching, or `scope_with_nesting` for nesting. Patching turns `.section { color: red; }` into `[data-capsule="abc123"] .section { color: red; }`. Nesting wraps the block as `[data-capsule="abc123"] { .section { color: red; } }`. Component integrations generate the id and wrap markup; see RFC 0004.

## Reference-level explanation

Capsule ids MUST be validated before use in attributes. CSS larger than `CssProcessor::MAX_CSS_SIZE` (1_000_000 bytes) MUST raise `ArgumentError`. CSS that would close a style element MUST be rejected before write into HTML. Comments are stripped on the patching path. Top-level at-rules such as `@media` are preserved; inner selectors are scoped. Already-scoped selectors that contain `[data-capsule=` are left alone. `:host`, `:host(...)`, and `:host-context(...)` map onto the capsule attribute. Nesting mode does not parse selectors; it wraps the whole string after the same size and breakout checks.

The default strategy is selector patching. Nesting is opt-in via `style_capsule scoping_strategy: :nesting` on the component (RFC 0004).

## Security considerations

Size limit bounds memory and rewrite work. Style-element breakout rejection blocks CSS that would escape a surrounding `<style>` tag. Capsule id validation and HTML escaping on wrappers prevent attribute injection through the id.

## Registrar

Public methods: `StyleCapsule::CssProcessor.scope_selectors`, `StyleCapsule::CssProcessor.scope_with_nesting`. Constant: `StyleCapsule::CssProcessor::MAX_CSS_SIZE`. Attribute: `data-capsule`.

## Drawbacks

Selector patching walks CSS with a regex-based rewriter; pathological input is mitigated by the size ceiling, not a full CSS parser. Nesting shifts compatibility onto the browser.

## Rationale and alternatives

Patching maximizes browser reach. Nesting avoids selector walks when the host accepts modern CSS nesting. A full CSS parser would be more correct and would cost dependency weight and hot-path latency. Class renaming was rejected in RFC 0002.

## Prior art

Angular emulated encapsulation; CSS nesting in browsers; Shadow DOM `:host`.

## Unresolved questions

Whether `@keyframes` and animation names should stay unscoped forever, or gain an opt-in rename strategy in a later RFC.
