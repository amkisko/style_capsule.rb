# frozen_string_literal: true

require "digest/sha1"
# Conditionally require ActiveSupport string extensions if available
# For non-Rails usage, these are optional
# Check first to avoid exception handling overhead in common case (Rails apps)
unless defined?(ActiveSupport) || String.method_defined?(:html_safe)
  begin
    require "active_support/core_ext/string"
  rescue LoadError
    # ActiveSupport not available - core functionality still works
  end
end

# StyleCapsule provides attribute-based CSS scoping for component encapsulation
# in Phlex components, ViewComponent components, and ERB templates.
#
# @example Phlex Component Usage
#   class MyComponent < ApplicationComponent
#     include StyleCapsule::Component
#
#     def component_styles
#       <<~CSS
#         .section { color: red; }
#       CSS
#     end
#   end
#
# @example ViewComponent Encapsulation Usage
#   class MyComponent < ApplicationComponent
#     include StyleCapsule::ViewComponent
#
#     def component_styles
#       <<~CSS
#         .section { color: red; }
#         .heading:hover { opacity: 0.8; }
#       CSS
#     end
#
#     def call
#       # Content is automatically wrapped in a scoped element
#       content_tag(:div, class: "section") do
#         content_tag(:h2, "Hello", class: "heading")
#       end
#     end
#   end
#
# @example ViewComponent Helper Usage (for stylesheet registry)
#   class ApplicationComponent < ViewComponent::Base
#     include StyleCapsule::ViewComponentHelper
#   end
#
#   class MyComponent < ApplicationComponent
#     def call
#       register_stylesheet("stylesheets/user/my_component")
#       content_tag(:div, "Content", class: "section")
#     end
#   end
#
# @example ERB Helper Usage
#   # Helpers are automatically included - no setup required
#   <%= style_capsule do %>
#     <style>.section { color: red; }</style>
#     <div class="section">Content</div>
#   <% end %>
#
#   <%= stylesheet_registry_tags %>
#   <%= stylesheet_registry_tags(namespace: :admin) %>
#
# @example Namespace Support
#   # Register stylesheets with namespaces
#   StyleCapsule::StylesheetRegistry.register('stylesheets/admin/dashboard', namespace: :admin)
#   StyleCapsule::StylesheetRegistry.register('stylesheets/user/profile', namespace: :user)
#
#   # Render all namespaces (default)
#   <%= stylesheet_registry_tags %>
#
#   # Render specific namespace
#   <%= stylesheet_registry_tags(namespace: :admin) %>
#
# @example File-Based Caching (HTTP Caching)
#   class MyComponent < ApplicationComponent
#     include StyleCapsule::Component
#     stylesheet_registry cache_strategy: :file  # Writes CSS to files for HTTP caching
#   end
#
#   # CSS files are written to app/assets/builds/capsules/
#   # Files are automatically precompiled via: bin/rails assets:precompile
#   # Or manually: bin/rails style_capsule:build
module StyleCapsule
  require_relative "style_capsule/version"
  require_relative "style_capsule/css_processor"
  require_relative "style_capsule/css_file_writer"
  require_relative "style_capsule/stylesheet_registry"
  require_relative "style_capsule/component_styles_support"
  require_relative "style_capsule/component"
  require_relative "style_capsule/standalone_helper"
  require_relative "style_capsule/helper"
  require_relative "style_capsule/phlex_helper"
  require_relative "style_capsule/view_component"
  require_relative "style_capsule/view_component_helper"
  require_relative "style_capsule/component_builder"
  require_relative "style_capsule/railtie" if defined?(Rails) && defined?(Rails::Railtie)
end
