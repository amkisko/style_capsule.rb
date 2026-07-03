# frozen_string_literal: true

require "digest/sha1"
require_relative "component_class_methods"
# ActiveSupport string extensions are conditionally required in lib/style_capsule.rb

module StyleCapsule
  # ViewComponent component concern for encapsulated CSS
  #
  # This implements attribute-based CSS scoping for component encapsulation:
  # - CSS selectors are rewritten to include [data-capsule="..."] attribute selectors
  # - Class names remain unchanged (no renaming)
  # - Scope ID is per-component-type (shared across all instances)
  # - Styles are rendered as <style> tag in body before component HTML
  # - Automatically wraps component content in a scoped wrapper element
  #
  # Usage in a ViewComponent component:
  #
  # Instance method (dynamic rendering, all cache strategies except :file):
  #
  #   class MyComponent < ApplicationComponent
  #     include StyleCapsule::ViewComponent
  #
  #     def component_styles
  #       <<~CSS
  #         .section {
  #           color: red;
  #         }
  #         .heading:hover {
  #           opacity: 0.8;
  #         }
  #       CSS
  #     end
  #   end
  #
  # Class method (static rendering, supports all cache strategies including :file):
  #
  #   class MyComponent < ApplicationComponent
  #     include StyleCapsule::ViewComponent
  #     stylesheet_registry cache_strategy: :file  # File caching requires class method
  #
  #     def self.component_styles
  #       <<~CSS
  #         .section {
  #           color: red;
  #         }
  #       CSS
  #     end
  #
  #     def call
  #       # Content is automatically wrapped in a scoped element
  #       # No need to manually add data-capsule attribute!
  #       content_tag(:div, class: "section") do
  #         content_tag(:h2, "Hello", class: "heading")
  #       end
  #     end
  #   end
  #
  # For testing with a custom scope ID:
  #
  #   class MyComponent < ApplicationComponent
  #     include StyleCapsule::ViewComponent
  #     capsule_id "test-capsule-123"  # Use exact capsule ID for testing
  #
  #     def component_styles
  #       <<~CSS
  #         .section { color: red; }
  #       CSS
  #     end
  #   end
  #
  # The CSS will be automatically rewritten from:
  #   .section { color: red; }
  #   .heading:hover { opacity: 0.8; }
  #
  # To:
  #   [data-capsule="a1b2c3d4"] .section { color: red; }
  #   [data-capsule="a1b2c3d4"] .heading:hover { opacity: 0.8; }
  #
  # And the HTML will be automatically wrapped:
  #   <div data-capsule="a1b2c3d4">
  #     <div class="section">...</div>
  #   </div>
  #
  # This ensures styles only apply to elements within the scoped component.
  module ViewComponent
    def self.included(base)
      base.extend(ClassMethods)
      base.include(ComponentStylesSupport)

      # Use prepend to wrap call method
      base.prepend(CallWrapper)

      # Register class for Rails-friendly tracking
      ClassRegistry.register(base)
    end

    module ClassMethods
      include StyleCapsule::ComponentClassMethods
    end

    # Module that wraps call to add scoped wrapper
    module CallWrapper
      def call
        if component_styles?
          # Render styles first
          styles_html = render_capsule_styles

          # Get content from original call method
          content_html = super

          # Get wrapper tag
          tag = self.class.wrapper_tag

          # Wrap content in scoped element
          scoped_wrapper = helpers.content_tag(tag, content_html.html_safe, data: {capsule: component_capsule})

          # Combine styles and wrapped content
          (styles_html + scoped_wrapper).html_safe
        else
          # No styles, render normally
          super
        end
      end
    end

    # Get the component capsule ID (per-component-type, shared across instances)
    #
    # All instances of the same component class share the same capsule ID.
    # Can be overridden with capsule_id class method for testing.
    #
    # @return [String] The capsule ID (e.g., "a1b2c3d4")
    def component_capsule
      return @component_capsule if defined?(@component_capsule)

      # Check for custom capsule ID set via class method
      @component_capsule = self.class.custom_capsule_id || generate_capsule_id
    end

    private

    # Render the style capsule <style> tag
    #
    # Can render in body (default) or register for head rendering via StylesheetRegistry
    #
    # Supports both instance method (def component_styles) and class method (def self.component_styles).
    # File caching is only allowed for class method component_styles.
    #
    # @return [String] HTML string with style tag or empty string
    # rubocop:disable Metrics/AbcSize -- coordinates head vs body rendering, caching, and registry
    def render_capsule_styles
      css_content = component_styles_content
      return "".html_safe if css_content.nil? || css_content.to_s.strip.empty?

      scoped_css = scope_css(css_content)
      capsule_id = component_capsule

      # Check if component uses head rendering
      if head_rendering?
        # Register for head rendering instead of rendering in body
        namespace = self.class.stylesheet_namespace

        # Get cache configuration from class
        cache_strategy = self.class.inline_cache_strategy || :none
        cache_ttl = self.class.inline_cache_ttl
        cache_proc = self.class.inline_cache_proc

        # File caching is only allowed for class method component_styles
        if cache_strategy == :file && !file_caching_allowed?
          # Fall back to :none strategy if file caching requested but not allowed
          cache_strategy = :none
          cache_ttl = nil
          cache_proc = nil
        end

        # Generate cache key based on component class and capsule
        cache_key = (cache_strategy != :none) ? "#{self.class.name}:#{capsule_id}" : nil

        StylesheetRegistry.register_inline(
          scoped_css,
          namespace: namespace,
          capsule_id: capsule_id,
          cache_key: cache_key,
          cache_strategy: cache_strategy,
          cache_ttl: cache_ttl,
          cache_proc: cache_proc,
          component_class: self.class,
          stylesheet_link_options: self.class.stylesheet_link_options
        )
        "".html_safe
      else
        # Render <style> tag in body (HTML5 allows this)
        helpers.content_tag(:style, scoped_css.html_safe, type: "text/css")
      end
    end
    # rubocop:enable Metrics/AbcSize

    # Check if component should use head rendering
    #
    # Checks class-level configuration first, then allows instance override.
    def head_rendering?
      return true if self.class.head_rendering?
      false
    end

    # Scope CSS and return scoped CSS with attribute selectors
    def scope_css(css_content)
      capsule_id = component_capsule
      scoping_strategy = self.class.css_scoping_strategy
      css_fingerprint = Digest::SHA1.hexdigest(css_content.to_s)
      cache_key = "#{self.class.name}:#{capsule_id}:#{scoping_strategy}:#{css_fingerprint}"

      if self.class.css_cache.key?(cache_key)
        return self.class.css_cache[cache_key]
      end

      # Use the configured scoping strategy
      scoped_css = case scoping_strategy
      when :nesting
        CssProcessor.scope_with_nesting(css_content, capsule_id, component_class: self.class)
      else # :selector_patching (default)
        CssProcessor.scope_selectors(css_content, capsule_id, component_class: self.class)
      end

      self.class.store_css_cache(cache_key, scoped_css)
    end

    # Generate a unique capsule ID based on component class name (per-component-type)
    #
    # This ensures all instances of the same component class share the same capsule ID,
    # similar to how component-based frameworks scope styles per component type.
    #
    # @return [String] The capsule ID (e.g., "a1b2c3d4")
    def generate_capsule_id
      class_name = self.class.name || self.class.object_id.to_s
      "a#{Digest::SHA1.hexdigest(class_name)}"[0, 8]
    end
  end
end
