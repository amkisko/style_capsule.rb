# RFC 0005: Stylesheet registry and head injection

- Feature Name: stylesheet-registry
- Type: Standards Track
- Status: Stable
- Created: 2026-09-25
- Author: Andrei Makarov
- Relates: RFC 0002, RFC 0004, RFC 0006

## Summary

Register stylesheets for `<head>` rendering with namespaces. Split boot-time paths (`register_eager`) from request-scoped paths and inline CSS (`register`). When layouts render head before body, `HeadInjectionMiddleware` injects pending request-scoped tags before `</head>` on bufferable 2xx HTML responses.

## Motivation

Inline `<style>` in the body duplicates work and blocks HTTP caching of shared CSS. Layouts typically call head helpers before the body runs, so render-time `register_stylesheet` would miss the head pass without a later injection step. Mixing admin, login, and user stylesheets in one bag causes leakage and weak cache keys. Hosts need namespace isolation and a clear eager versus request boundary.

## Guide-level explanation

At boot or class load: `StyleCapsule::StylesheetRegistry.register_eager("stylesheets/admin/dashboard", namespace: :admin)`. During render: `register_stylesheet("stylesheets/user/page")` (namespace from `style_capsule` when omitted). In the layout: `stylesheet_registry_tags(namespace: :admin)`. With middleware enabled (default on Rails), omit a premature clear of request-scoped tags when Phlex capture would drop them; let injection append pending tags before `</head>`. Disable with `config.style_capsule.head_injection_middleware = false` when the host buffers or streams itself. Manual path: `StylesheetRegistry.inject_pending_head_stylesheets`.

## Reference-level explanation

Eager registrations live in a process-wide manifest keyed by namespace and logical path. Request-scoped file paths and inline CSS live per request (`ActiveSupport::CurrentAttributes` when available; thread-local fallback otherwise). Rendering a namespace emits link tags for files and style tags for inline CSS. Logical paths MUST reject parent segments (`..`). Duplicate logical paths dedupe; request registration wins option conflicts. Inline stylesheet cache is bounded (`MAX_INLINE_CACHE_ENTRIES` = 256).

`HeadInjectionMiddleware` rewrites only when pending request-scoped stylesheets remain and the Rack body responds to `to_ary`. After rewrite it sets `Content-Length` and removes `Transfer-Encoding`. Non-bufferable streaming bodies (Live, SSE, and similar) are left alone. Injection accepts 2xx HTML. Holding the full body in memory is the cost of rewrite.

## Security considerations

`AssetPath.validate_logical_path!` rejects traversal. Fallback link attributes are escaped and name-restricted. Capsule and CSS rules from RFC 0003 apply to inline CSS written into head.

## Registrar

Public methods: `StylesheetRegistry.register`, `StylesheetRegistry.register_eager`, `StylesheetRegistry.render_head_stylesheets`, `StylesheetRegistry.inject_pending_head_stylesheets`, `register_stylesheet`, `stylesheet_registry_tags`. Class: `StyleCapsule::HeadInjectionMiddleware`. Config: `config.style_capsule.head_injection_middleware`.

## Drawbacks

Middleware buffering trades latency and memory for correct head placement. Streaming responses need a host-owned injection path. Eager versus request split is a breaking mental model for hosts that called `register` at boot before 2.0.0.

## Rationale and alternatives

Always buffering every HTML response would waste memory when nothing is pending. Only documenting "call head after body" would fight Rails layout order. A single `register` for boot and request mixed process-wide and per-request state. Propshaft-like manifests inspired the eager map; request scope covers dynamic paths.

## Prior art

Propshaft and Sprockets stylesheet tags; Rack middleware body rewriters; Turbo track attributes on stylesheet links.

## Unresolved questions

Whether injection should gain a documented size ceiling for rewritten bodies beyond "full 2xx HTML in memory".

Whether a non-Rails Rack adapter for the middleware deserves its own RFC.
