# style_capsule

[![Gem Version](https://badge.fury.io/rb/style_capsule.svg?v=1.4.0)](https://badge.fury.io/rb/style_capsule) [![Test Status](https://github.com/amkisko/style_capsule.rb/actions/workflows/test.yml/badge.svg)](https://github.com/amkisko/style_capsule.rb/actions/workflows/test.yml) [![codecov](https://codecov.io/gh/amkisko/style_capsule.rb/graph/badge.svg?token=2U6NXJOVVM)](https://codecov.io/gh/amkisko/style_capsule.rb)

CSS scoping extension for Ruby components. Provides attribute-based style encapsulation for Phlex, ViewComponent, and ERB templates to prevent style leakage between components. Works with Rails and can be used standalone in other Ruby frameworks (Sinatra, Hanami, etc.) or plain Ruby scripts. Includes configurable caching strategies for optimal performance.

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>

## Installation

Add to your Gemfile:

```ruby
gem "style_capsule"
```

Then run `bundle install`.

## Features

- **Attribute-based CSS scoping** (no class name renaming)
- **Phlex, ViewComponent, and ERB support** with automatic Rails integration
- **Per-component-type scope IDs** (shared across instances)
- **CSS Nesting support** (optional, more performant, requires modern browsers)
- **Stylesheet registry** with thread-safe head rendering, namespace support, and compatibility with Propshaft and other asset bundlers
- **Multiple cache strategies**: none, time-based, custom proc, and file-based (HTTP caching)
- **Comprehensive instrumentation** via ActiveSupport::Notifications for monitoring and metrics
- **Fallback directory support** for read-only filesystems (e.g., Docker containers)
- **Security protections**: path traversal protection, input validation, size limits

## Usage

### Phlex Components

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::Component

  def component_styles
    <<~CSS
      .section { color: red; }
      .heading:hover { opacity: 0.8; }
    CSS
  end

  def view_template
    div(class: "section") do
      h2(class: "heading") { "Hello" }
    end
  end
end
```

CSS is automatically scoped with `[data-capsule="..."]` attributes and content is wrapped in a scoped element.

### ViewComponent

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::ViewComponent

  def component_styles
    <<~CSS
      .section { color: red; }
    CSS
  end

  def call
    content_tag :div, class: "section" do
      "Hello"
    end
  end
end
```

### ERB Templates

```erb
<%= style_capsule do %>
  <style>
    .section { color: red; }
  </style>
  <div class="section">Content</div>
<% end %>
```

**With custom wrapper tag:**

```erb
<%= style_capsule(tag: :section) do %>
  <style>
    .section { color: red; }
  </style>
  <div class="section">Content</div>
<% end %>
```

## CSS Scoping Strategies

StyleCapsule supports two CSS scoping strategies:

1. **Selector Patching (default)**: Adds `[data-capsule="..."]` prefix to each selector
   - Better browser support (all modern browsers)
   - Output: `[data-capsule="abc123"] .section { color: red; }`

2. **CSS Nesting (optional)**: Wraps entire CSS in `[data-capsule="..."] { ... }`
   - More performant (no CSS parsing needed)
   - Requires CSS nesting support (Chrome 112+, Firefox 117+, Safari 16.5+)
   - Output: `[data-capsule="abc123"] { .section { color: red; } }`

### Configuration

**Per-component (using `style_capsule` - recommended):**

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::Component
  style_capsule scoping_strategy: :nesting  # Use CSS nesting
end
```

**With custom wrapper tag:**

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::Component
  style_capsule tag: :section  # Use <section> instead of <div> for wrapper
end
```

**Global (in base component class):**

```ruby
class ApplicationComponent < Phlex::HTML
  include StyleCapsule::Component
  style_capsule scoping_strategy: :nesting  # Enable for all components
end
```

**Note:** If you change the strategy and it doesn't take effect, clear the CSS cache:

```ruby
MyComponent.clear_css_cache
```

## Stylesheet Registry

For better performance, register styles for head rendering instead of rendering `<style>` tags in the body. Use the unified `style_capsule` method to configure all settings:

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::Component
  style_capsule namespace: :admin  # Configure namespace and enable head rendering

  def component_styles
    <<~CSS
      .section { color: red; }
    CSS
  end
end
```

With cache strategy and CSS scoping:

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::Component
  style_capsule(
    namespace: :admin,
    cache_strategy: :time,
    cache_ttl: 1.hour,
    scoping_strategy: :nesting
  )

  def component_styles
    <<~CSS
      .section { color: red; }
    CSS
  end
end
```

Then in your layout (render only the namespace you need):

```erb
<head>
  <%= stylesheet_registry_tags(namespace: :admin) %>
</head>
```

Or in Phlex (requires including `StyleCapsule::PhlexHelper`):

```ruby
head do
  stylesheet_registry_tags(namespace: :admin)
end
```

**Namespace Isolation:** Using namespaces prevents stylesheet leakage between different application contexts. For example, login pages can use `namespace: :login`, ActiveAdmin can use `namespace: :active_admin`, and user components can use `namespace: :user`. Each namespace is rendered separately, improving caching efficiency and preventing style conflicts.

### Registering Stylesheet Files

You can also register external stylesheet files (not inline CSS) for head rendering. When a component has a configured namespace via `style_capsule`, you don't need to specify it every time:

**In ERB:**

```erb
<% register_stylesheet("stylesheets/user/my_component", "data-turbo-track": "reload") %>
<% register_stylesheet("stylesheets/admin/dashboard", namespace: :admin) %>
```

**In Phlex (requires including `StyleCapsule::PhlexHelper`):**

```ruby
class UserComponent < ApplicationComponent
  include StyleCapsule::Component
  include StyleCapsule::PhlexHelper
  style_capsule namespace: :user  # Set default namespace

  def view_template
    # Namespace automatically uses :user from style_capsule
    register_stylesheet("stylesheets/user/my_component", "data-turbo-track": "reload")
    # Can still override namespace if needed
    register_stylesheet("stylesheets/shared/common", namespace: :shared)
    div { "Content" }
  end
end
```

**In ViewComponent (requires including `StyleCapsule::ViewComponentHelper`):**

```ruby
class UserComponent < ApplicationComponent
  include StyleCapsule::ViewComponent
  include StyleCapsule::ViewComponentHelper
  style_capsule namespace: :user  # Set default namespace

  def call
    # Namespace automatically uses :user from style_capsule
    register_stylesheet("stylesheets/user/my_component", "data-turbo-track": "reload")
    content_tag(:div, "Content")
  end
end
```

Registered files are rendered via `stylesheet_registry_tags` in your layout, just like inline CSS. The namespace is automatically used from the component's `style_capsule` configuration when not explicitly specified.

## Caching Strategies

### No Caching (Default)

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::Component
  style_capsule  # No cache strategy set (default: :none)
end
```

### Time-Based Caching

```ruby
style_capsule cache_strategy: :time, cache_ttl: 1.hour  # Using ActiveSupport::Duration
# Or using integer seconds:
style_capsule cache_strategy: :time, cache_ttl: 3600  # Cache for 1 hour
```

### Custom Proc Caching

```ruby
style_capsule cache_strategy: ->(css, capsule_id, namespace) {
  cache_key = "css_#{capsule_id}_#{namespace}"
  should_cache = css.length > 100
  expires_at = Time.now + 1800
  [cache_key, should_cache, expires_at]
}
```

**Note:** `cache_strategy` accepts Symbol (`:time`), String (`"time"`), or Proc. Strings are automatically converted to symbols.

### File-Based Caching (HTTP Caching)

Writes CSS to files for HTTP caching. **Requires class method `def self.component_styles`**:

```ruby
class MyComponent < ApplicationComponent
  include StyleCapsule::Component
  style_capsule cache_strategy: :file

  # Must use class method for file caching
  def self.component_styles
    <<~CSS
      .section { color: red; }
    CSS
  end
end
```

**Configuration:**

```ruby
# config/initializers/style_capsule.rb
StyleCapsule::CssFileWriter.configure(
  output_dir: Rails.root.join("app/assets/builds/capsules"),
  filename_pattern: ->(component_class, capsule_id) {
    "capsule-#{capsule_id}.css"
  },
  fallback_dir: "/tmp/style_capsule"  # Optional, defaults to /tmp/style_capsule
)
```

**Fallback Directory:** In production environments where the app directory is read-only (e.g., Docker containers), StyleCapsule automatically falls back to writing files to `/tmp/style_capsule` when the default location is not writable. When using the fallback directory, the gem gracefully falls back to inline CSS rendering, keeping the UI fully functional.

**Precompilation:**

```bash
bin/rails style_capsule:build  # Build CSS files
bin/rails style_capsule:clear  # Clear generated files
```

Files are automatically built during `bin/rails assets:precompile`.

**Compatibility:** The stylesheet registry works with Propshaft, Sprockets, and other Rails asset bundlers. Static file paths are collected in a process-wide manifest (similar to Propshaft's approach), while inline CSS is stored per-request.

## Instrumentation

StyleCapsule provides comprehensive instrumentation via `ActiveSupport::Notifications` for monitoring CSS processing and file writing operations. All instrumentation is zero-overhead when no subscribers are present.

### Available Events

- `style_capsule.css_processor.scope` - CSS scoping operations with duration and size metrics
- `style_capsule.css_file_writer.write` - CSS file write operations with duration and size metrics
- `style_capsule.css_file_writer.fallback` - When fallback directory is used (read-only filesystem)
- `style_capsule.css_file_writer.fallback_failure` - When both primary and fallback directories fail
- `style_capsule.css_file_writer.write_failure` - Other write errors

### Example: Monitoring CSS Processing

```ruby
# config/initializers/style_capsule.rb
ActiveSupport::Notifications.subscribe("style_capsule.css_processor.scope") do |name, start, finish, id, payload|
  duration_ms = (finish - start) * 1000
  Rails.logger.info "CSS scoped in #{duration_ms.round(2)}ms, input: #{payload[:input_size]} bytes, output: #{payload[:output_size]} bytes"
end
```

### Example: Monitoring File Writes

```ruby
ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.write") do |name, start, finish, id, payload|
  duration_ms = (finish - start) * 1000
  StatsD.timing("style_capsule.write.duration", duration_ms)
  StatsD.histogram("style_capsule.write.size", payload[:size])
end
```

### Example: Monitoring Fallback Scenarios

```ruby
ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.fallback") do |name, start, finish, id, payload|
  Rails.logger.warn "StyleCapsule fallback used: #{payload[:component_class]} -> #{payload[:fallback_path]}"
  # Exception info available: payload[:exception] and payload[:exception_object]
  StatsD.increment("style_capsule.css_file_writer.fallback", tags: [
    "component:#{payload[:component_class]}",
    "error:#{payload[:exception].first}"
  ])
end
```

### Example: Error Reporting

```ruby
ActiveSupport::Notifications.subscribe("style_capsule.css_file_writer.fallback_failure") do |name, start, finish, id, payload|
  ActionReporter.notify(
    "StyleCapsule: CSS write failure (both primary and fallback failed)",
    context: {
      component_class: payload[:component_class],
      original_path: payload[:original_path],
      fallback_path: payload[:fallback_path],
      original_exception: payload[:original_exception],
      fallback_exception: payload[:fallback_exception]
    }
  )
end
```

For more details, see the [ActiveSupport::Notifications documentation](https://guides.rubyonrails.org/active_support_instrumentation.html).

## Advanced Usage

### Database-Stored CSS

For CSS stored in a database (e.g., user-generated styles, themes), use StyleCapsule's CSS processor directly:

```ruby
# app/models/theme.rb
class Theme < ApplicationRecord
  def generate_capsule_id
    return capsule_id if capsule_id.present?
    scope_key = "theme_#{id}_#{name}"
    self.capsule_id = "a#{Digest::SHA1.hexdigest(scope_key)}"[0, 8]
    save! if persisted?
    capsule_id
  end

  def scoped_css
    return scoped_css_cache if scoped_css_cache.present? && 
                               scoped_css_updated_at == updated_at
    
    current_capsule_id = generate_capsule_id
    scoped = StyleCapsule::CssProcessor.scope_selectors(css_content, current_capsule_id)
    
    update_columns(
      scoped_css_cache: scoped,
      scoped_css_updated_at: updated_at,
      capsule_id: current_capsule_id
    )
    
    scoped
  end
end
```

**Usage:**

```erb
<div data-capsule="<%= theme.capsule_id %>">
  <style><%= raw theme.scoped_css %></style>
  <div class="header">Content</div>
</div>
```

## CSS Selector Support

- Regular selectors: `.section`, `#header`, `div.container`
- Pseudo-classes and pseudo-elements: `.button:hover`, `.item::before`
- Multiple selectors: `.a, .b, .c { color: red; }`
- Component-scoped selectors: `:host`, `:host(.active)`, `:host-context(.theme-dark)`
- Media queries: `@media (max-width: 768px) { ... }`

## Requirements

- Ruby >= 3.0
- Rails >= 6.0, < 9.0 (optional, for Rails integration)
- ActiveSupport >= 6.0, < 9.0 (optional, for Rails integration)

**Note**: The gem can be used without Rails! See [Non-Rails Support](#non-rails-support) below.

## Non-Rails Support

StyleCapsule can be used without Rails! The core functionality is framework-agnostic.

### Standalone Usage

```ruby
require 'style_capsule'

# Direct CSS processing
css = ".section { color: red; }"
capsule_id = "abc123"
scoped = StyleCapsule::CssProcessor.scope_selectors(css, capsule_id)
# => "[data-capsule=\"abc123\"] .section { color: red; }"
```

### Phlex Without Rails

```ruby
require 'phlex'
require 'style_capsule'

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

### Sinatra

```ruby
require 'sinatra'
require 'style_capsule'

class MyApp < Sinatra::Base
  helpers StyleCapsule::StandaloneHelper
  
  get '/' do
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

### Stylesheet Registry Without Rails

The stylesheet registry automatically uses thread-local storage when ActiveSupport is not available:

```ruby
require 'style_capsule'

# Works without Rails
StyleCapsule::StylesheetRegistry.register_inline(".test { color: red; }", namespace: :test)
stylesheets = StyleCapsule::StylesheetRegistry.request_inline_stylesheets
```

For more details, see [docs/non_rails_support.md](docs/non_rails_support.md).

## How It Works

1. **Scope ID Generation**: Each component class gets a unique scope ID based on its class name (shared across all instances)
2. **CSS Rewriting**: CSS selectors are rewritten to include `[data-capsule="..."]` attribute selectors
3. **HTML Wrapping**: Component content is automatically wrapped in a scoped element
4. **No Class Renaming**: Class names remain unchanged (unlike Shadow DOM)

## Development

```bash
bundle install
bundle exec appraisal install

# Run tests
bundle exec rspec

# Run tests for all Rails versions
bundle exec appraisal rails72 rspec
bundle exec appraisal rails8ruby34 rspec

# Linting
bundle exec standardrb --fix
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/amkisko/style_capsule.rb

Contribution policy:
- New features are not necessarily added to the gem
- Pull requests should have test coverage and changelog entry

Review policy:
- Critical fixes: up to 2 calendar weeks
- Pull requests: up to 6 calendar months
- Issues: up to 1 calendar year

## Publishing

```sh
rm style_capsule-*.gem
gem build style_capsule.gemspec
gem push style_capsule-*.gem
```

## Security

StyleCapsule includes security protections:
- Path traversal protection
- Input validation
- Size limits (1MB per component)
- XSS prevention via Rails' HTML escaping

For detailed security information, see [SECURITY.md](SECURITY.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
