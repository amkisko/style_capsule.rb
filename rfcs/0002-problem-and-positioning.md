# RFC 0002: Problem and positioning

- Feature Name: problem-and-positioning
- Type: Informational
- Status: Stable
- Created: 2026-09-25
- Author: Andrei Makarov
- Relates: RFC 0003, RFC 0004, RFC 0005, RFC 0006

## Summary

Scope component CSS with attribute selectors so class names stay stable and styles do not leak across components. The gem works with Phlex, ViewComponent, and ERB on Rails or standalone Ruby. It does not rename classes and does not require Shadow DOM.

## Motivation

Shared class names across components collide. Global stylesheets and unscoped `<style>` tags leak into unrelated markup. Shadow DOM encapsulates styles but changes hosting and selector rules hosts already wrote. Class-renaming pipelines (CSS Modules, many build-time scopes) rewrite class strings and break templates that share class names with design systems or third-party CSS.

Hosts need one encapsulation path across Phlex, ViewComponent, and ERB without a separate build step for every template language. They also need optional head rendering, namespaces, and cache strategies so large apps do not pay inline `<style>` cost on every body fragment.

Those choices are the public contract: `data-capsule` attribute scoping, the `style_capsule` class method, stylesheet registry registration, head injection, and cache strategies. Changing any of them without a numbered RFC breaks existing components and layouts.

## Guide-level explanation

Include `StyleCapsule::Component` (Phlex), `StyleCapsule::ViewComponent`, or use the ERB helper. Define `component_styles` (or pass CSS into the helper). Render. Markup gets a `data-capsule` attribute. Selectors gain a matching attribute prefix (or nesting wrapper). Optionally call `style_capsule` with a namespace and render `stylesheet_registry_tags` in the layout head.

## Drawbacks

Attribute selectors add specificity and a small rewrite cost on the selector-patching path. Nesting mode needs modern browser support. Head injection buffers bufferable HTML bodies when pending request-scoped stylesheets exist.

## Rationale and alternatives

Attribute encapsulation keeps class names readable and matches emulated view encapsulation hosts already know from Angular-style tooling. Shadow DOM would isolate better and would force hosts off plain CSS and existing class contracts. Build-time class renaming would shrink selector strings and would break shared design-system class names. Doing nothing leaves hosts hand-prefixing selectors or accepting leakage.

## Prior art

Angular emulated view encapsulation; CSS Modules and scoped CSS in Vue and Svelte; Shadow DOM; Propshaft-style asset path registration for head tags. Contract detail is RFC 0003 through RFC 0006.

## Unresolved questions

Whether a standards-track RFC should freeze the exact set of supported CSS at-rules beyond media queries when a full CSS parser replaces the current rewrite.

Whether non-Rails adapters beyond the standalone helper need their own RFC when a second framework integration ships.
