# Non-Rails usage

StyleCapsule works without Rails. Core APIs are framework-agnostic; optional pieces integrate with Rails when `railties` and `activesupport` are present.

## Direct CSS processing

```ruby
require "style_capsule"

css = ".section { color: red; }"
capsule_id = "abc123"
scoped = StyleCapsule::CssProcessor.scope_selectors(css, capsule_id)
# => "[data-capsule=\"abc123\"] .section { color: red; }"
```

## Phlex (`StyleCapsule::Component`)

```ruby
require "phlex"
require "style_capsule"

class MyComponent < Phlex::HTML
  include StyleCapsule::Component

  def component_styles
    <<~CSS
      .section { color: red; }
    CSS
  end

  def view_template
    div(class: "section") { "Hello" }
  end
end
```

## Sinatra and `StyleCapsule::StandaloneHelper`

Use `StyleCapsule::StandaloneHelper` for ERB (or similar) without ActionView. It mirrors the Rails `Helper` API, including `style_capsule(tag: :section)` for a custom wrapper element.

```ruby
require "sinatra"
require "style_capsule"

class MyApp < Sinatra::Base
  helpers StyleCapsule::StandaloneHelper

  get "/" do
    erb :index
  end
end
```

```erb
<!-- views/index.erb -->
<%= style_capsule do %>
  <style>
    .section { color: red; }
  </style>
  <div class="section">Content</div>
<% end %>
```

## Stylesheet registry without Rails

When `ActiveSupport::CurrentAttributes` is not loaded, `StyleCapsule::StylesheetRegistry` uses thread-local storage for request-scoped inline CSS and render-time file paths. Use `register_eager` for process-wide file paths that should appear on every request (boot or class load). Use `register` during rendering when a component calls `register_stylesheet`.

```ruby
require "style_capsule"

# Boot-time / static file (process-wide manifest)
StyleCapsule::StylesheetRegistry.register_eager("stylesheets/main", namespace: :default)

# Render-time registration (same request only)
StyleCapsule::StylesheetRegistry.register("stylesheets/page", namespace: :default)

# Inline CSS (request-scoped)
StyleCapsule::StylesheetRegistry.register_inline(".test { color: red; }", namespace: :test)
stylesheets = StyleCapsule::StylesheetRegistry.request_inline_stylesheets
```

## Configuration entry points

- **`style_capsule`** — Preferred class-level DSL for namespace, cache strategy, CSS scoping (`:selector_patching` or `:nesting`), head rendering, and wrapper `tag:`.
- **`stylesheet_registry`** — Older alias that enables head rendering and cache options; new code should prefer `style_capsule` for a single configuration surface.
