#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using StyleCapsule without Rails
#
# This demonstrates how to use StyleCapsule in non-Rails contexts:
# - Plain Ruby scripts
# - Sinatra applications
# - Phlex standalone
# - Any framework that supports ERB

require "style_capsule"

# ============================================================================
# Example 1: Direct CSS Processing (No Framework)
# ============================================================================

puts "=" * 80
puts "Example 1: Direct CSS Processing"
puts "=" * 80

css = <<~CSS
  .section { color: red; }
  .heading:hover { opacity: 0.8; }
CSS

capsule_id = "abc123"
scoped_css = StyleCapsule::CssProcessor.scope_selectors(css, capsule_id)

puts "Original CSS:"
puts css
puts "\nScoped CSS:"
puts scoped_css
puts "\n"

# ============================================================================
# Example 2: Using Standalone Helper (Plain Ruby)
# ============================================================================

puts "=" * 80
puts "Example 2: Using Standalone Helper"
puts "=" * 80

class SimpleView
  include StyleCapsule::StandaloneHelper

  def render
    style_capsule do
      "<style>.section { color: red; }</style><div class='section'>Hello World</div>"
    end
  end
end

view = SimpleView.new
html = view.render
puts "Generated HTML:"
puts html
puts "\n"

# ============================================================================
# Example 3: Phlex Component (Standalone)
# ============================================================================

puts "=" * 80
puts "Example 3: Phlex Component (Standalone)"
puts "=" * 80

begin
  require "phlex"

  class MyPhlexComponent < Phlex::HTML
    include StyleCapsule::Component

    def component_styles
      <<~CSS
        .section { color: red; }
        .heading { font-size: 24px; }
      CSS
    end

    def view_template
      div(class: "section") do
        h2(class: "heading") { "Hello from Phlex" }
      end
    end
  end

  component = MyPhlexComponent.new
  puts "Phlex Component HTML:"
  puts component.call
  puts "\n"
rescue LoadError
  puts "Phlex not available - skipping Phlex example"
  puts "Install with: gem install phlex"
  puts "\n"
end

# ============================================================================
# Example 4: Sinatra Integration
# ============================================================================

puts "=" * 80
puts "Example 4: Sinatra Integration"
puts "=" * 80

begin
  require "sinatra"

  class MySinatraApp < Sinatra::Base
    helpers StyleCapsule::StandaloneHelper

    get "/" do
      erb :index
    end
  end

  puts "Sinatra app created with StyleCapsule helper"
  puts "Include in your Sinatra app:"
  puts "  helpers StyleCapsule::StandaloneHelper"
  puts "\n"
rescue LoadError
  puts "Sinatra not available - skipping Sinatra example"
  puts "Install with: gem install sinatra"
  puts "\n"
end

# ============================================================================
# Example 5: ERB Template (Non-Rails)
# ============================================================================

puts "=" * 80
puts "Example 5: ERB Template (Non-Rails)"
puts "=" * 80

begin
  require "erb"

  class ERBContext
    include StyleCapsule::StandaloneHelper

    def get_binding
      binding
    end
  end

  template = <<~ERB
    <!DOCTYPE html>
    <html>
    <head>
      <title>StyleCapsule Example</title>
    </head>
    <body>
      <%= style_capsule do %>
        <style>
          .section { color: red; }
          .heading { font-size: 24px; }
        </style>
        <div class="section">
          <h1 class="heading">Hello from ERB</h1>
        </div>
      <% end %>
    </body>
    </html>
  ERB

  context = ERBContext.new
  erb = ERB.new(template)
  result = erb.result(context.get_binding)

  puts "ERB Template Result:"
  puts result
  puts "\n"
rescue LoadError
  puts "ERB not available - skipping ERB example"
  puts "\n"
end

# ============================================================================
# Example 6: Stylesheet Registry (Non-Rails)
# ============================================================================

puts "=" * 80
puts "Example 6: Stylesheet Registry (Non-Rails)"
puts "=" * 80

# Register stylesheets
StyleCapsule::StylesheetRegistry.register("stylesheets/main", namespace: :default)
StyleCapsule::StylesheetRegistry.register("stylesheets/admin", namespace: :admin)

# Render stylesheets
class HeadRenderer
  include StyleCapsule::StandaloneHelper
end

renderer = HeadRenderer.new
stylesheets = renderer.stylesheet_registrymap_tags

puts "Registered Stylesheets:"
puts stylesheets
puts "\n"

puts "=" * 80
puts "All examples completed!"
puts "=" * 80
