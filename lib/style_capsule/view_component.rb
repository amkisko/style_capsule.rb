# frozen_string_literal: true

require "digest/sha1"
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
      # Class-level cache for scoped CSS per component class
      def css_cache
        @css_cache ||= {}
      end

      # Clear the CSS cache for this component class
      #
      # Useful for testing or when you want to force CSS reprocessing.
      # In development, this is automatically called when classes are reloaded.
      #
      # @example
      #   MyComponent.clear_css_cache
      def clear_css_cache
        @css_cache = {}
      end

      # Set or get a custom capsule ID for this component class (useful for testing)
      #
      # @param capsule_id [String, nil] The custom capsule ID to use (nil to get current value)
      # @return [String, nil] The current capsule ID if no argument provided
      # @example Setting a custom capsule ID
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     capsule_id "test-capsule-123"
      #   end
      # @example Getting the current capsule ID
      #   MyComponent.capsule_id  # => "test-capsule-123" or nil
      def capsule_id(capsule_id = nil)
        if capsule_id.nil?
          @custom_capsule_id if defined?(@custom_capsule_id)
        else
          @custom_capsule_id = capsule_id.to_s
        end
      end

      # Configure stylesheet registry for head rendering
      #
      # Enables head rendering and configures namespace and cache strategy in a single call.
      # All parameters are optional - calling without arguments enables head rendering with defaults.
      #
      # @param namespace [Symbol, String, nil] Namespace identifier (nil/blank uses default)
      # @param cache_strategy [Symbol, String, Proc, nil] Cache strategy: :none (default), :time, :proc, :file
      #   - Symbol or String: :none, :time, :proc, :file (or "none", "time", "proc", "file")
      #   - Proc: Custom cache proc (automatically uses :proc strategy)
      #     Proc receives: (css_content, capsule_id, namespace) and should return [cache_key, should_cache, expires_at]
      # @param cache_ttl [Integer, ActiveSupport::Duration, nil] Time-to-live in seconds (for :time strategy). Supports ActiveSupport::Duration (e.g., 1.hour, 30.minutes)
      # @param cache_proc [Proc, nil] Custom cache proc (for :proc strategy, ignored if cache_strategy is a Proc)
      #   Proc receives: (css_content, capsule_id, namespace) and should return [cache_key, should_cache, expires_at]
      # @return [void]
      # @example Basic usage (enables head rendering with defaults)
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     stylesheet_registry
      #   end
      # @example With namespace
      #   class AdminComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     stylesheet_registry namespace: :admin
      #   end
      # @example With time-based caching
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     stylesheet_registry cache_strategy: :time, cache_ttl: 1.hour
      #   end
      # @example With custom proc caching
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     stylesheet_registry cache_strategy: :proc, cache_proc: ->(css, capsule_id, ns) {
      #       cache_key = "css_#{capsule_id}_#{ns}"
      #       should_cache = css.length > 100
      #       expires_at = Time.now + 1800
      #       [cache_key, should_cache, expires_at]
      #     }
      #   end
      # @example File-based caching (requires class method component_styles)
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     stylesheet_registry cache_strategy: :file
      #
      #     def self.component_styles  # Must be class method for file caching
      #       <<~CSS
      #         .section { color: red; }
      #       CSS
      #     end
      #   end
      # @example All options combined
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     stylesheet_registry namespace: :admin, cache_strategy: :time, cache_ttl: 1.hour
      #   end
      def stylesheet_registry(namespace: nil, cache_strategy: :none, cache_ttl: nil, cache_proc: nil)
        @head_rendering = true
        @stylesheet_namespace = namespace unless namespace.nil?

        # Normalize cache_strategy: convert strings to symbols, handle Proc
        normalized_strategy, normalized_proc = normalize_cache_strategy(cache_strategy, cache_proc)
        @inline_cache_strategy = normalized_strategy
        @inline_cache_ttl = cache_ttl
        @inline_cache_proc = normalized_proc
      end

      private

      # Normalize cache_strategy to handle Symbol, String, and Proc
      #
      # @param cache_strategy [Symbol, String, Proc, nil] Cache strategy
      # @param cache_proc [Proc, nil] Optional cache proc (ignored if cache_strategy is a Proc)
      # @return [Array<Symbol, Proc|nil>] Normalized strategy and proc
      def normalize_cache_strategy(cache_strategy, cache_proc)
        case cache_strategy
        when Proc
          # If cache_strategy is a Proc, use it as the proc and set strategy to :proc
          [:proc, cache_strategy]
        when String
          # Convert string to symbol
          normalized = cache_strategy.to_sym
          unless [:none, :time, :proc, :file].include?(normalized)
            raise ArgumentError, "cache_strategy must be :none, :time, :proc, or :file (got: #{cache_strategy.inspect})"
          end
          [normalized, cache_proc]
        when Symbol
          unless [:none, :time, :proc, :file].include?(cache_strategy)
            raise ArgumentError, "cache_strategy must be :none, :time, :proc, or :file (got: #{cache_strategy.inspect})"
          end
          [cache_strategy, cache_proc]
        when nil
          [:none, nil]
        else
          raise ArgumentError, "cache_strategy must be a Symbol, String, or Proc (got: #{cache_strategy.class})"
        end
      end

      # Deprecated: Use stylesheet_registry instead
      # @deprecated Use {#stylesheet_registry} instead
      def head_rendering!
        stylesheet_registry
      end

      # Check if component uses head rendering
      def head_rendering?
        return false unless defined?(@head_rendering)
        @head_rendering
      end

      public :head_rendering?

      # Get the namespace for stylesheet registry
      def stylesheet_namespace
        @stylesheet_namespace if defined?(@stylesheet_namespace)
      end

      # Configure StyleCapsule settings
      #
      # @param namespace [Symbol, String, nil] Default namespace for stylesheets
      # @param cache_strategy [Symbol, String, Proc, nil] Cache strategy: :none (default), :time, :proc, :file
      # @param cache_ttl [Integer, ActiveSupport::Duration, nil] Time-to-live in seconds (for :time strategy)
      # @param cache_proc [Proc, nil] Custom cache proc (for :proc strategy)
      # @param css_scoping_strategy [Symbol, nil] CSS scoping strategy: :selector_patching (default) or :nesting
      # @param head_rendering [Boolean, nil] Enable head rendering (default: true if any option is set, false otherwise)
      # @return [void]
      # @example Basic usage with namespace
      #   class AdminComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     style_capsule namespace: :admin
      #
      #     def call
      #       register_stylesheet("stylesheets/admin/dashboard")  # Uses :admin namespace automatically
      #       content_tag(:div, "Content")
      #     end
      #   end
      # @example With all options
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     style_capsule(
      #       namespace: :user,
      #       cache_strategy: :time,
      #       cache_ttl: 1.hour,
      #       css_scoping_strategy: :nesting
      #     )
      #   end
      def style_capsule(namespace: nil, cache_strategy: nil, cache_ttl: nil, cache_proc: nil, css_scoping_strategy: nil, head_rendering: nil)
        # Set namespace (instance variable, not inherited - each class has its own)
        if namespace
          @stylesheet_namespace = namespace
        end

        # Configure cache strategy if provided
        if cache_strategy || cache_ttl || cache_proc
          normalized_strategy, normalized_proc = normalize_cache_strategy(cache_strategy || :none, cache_proc)
          @inline_cache_strategy = normalized_strategy
          @inline_cache_ttl = cache_ttl
          @inline_cache_proc = normalized_proc
        end

        # Configure CSS scoping strategy if provided
        if css_scoping_strategy
          self.css_scoping_strategy(css_scoping_strategy)
        end

        # Enable head rendering if explicitly set or if any option is provided
        if head_rendering.nil?
          @head_rendering = true if namespace || cache_strategy || cache_ttl || cache_proc
        else
          @head_rendering = head_rendering
        end
      end

      # Get the custom scope ID if set (alias for capsule_id getter)
      def custom_capsule_id
        @custom_capsule_id if defined?(@custom_capsule_id)
      end

      # Get inline cache strategy
      def inline_cache_strategy
        @inline_cache_strategy if defined?(@inline_cache_strategy)
      end

      # Get inline cache TTL
      def inline_cache_ttl
        @inline_cache_ttl if defined?(@inline_cache_ttl)
      end

      # Get inline cache proc
      def inline_cache_proc
        @inline_cache_proc if defined?(@inline_cache_proc)
      end

      public :head_rendering?, :stylesheet_namespace, :style_capsule, :custom_capsule_id, :inline_cache_strategy, :inline_cache_ttl, :inline_cache_proc

      # Set or get options for stylesheet_link_tag when using file-based caching
      #
      # @param options [Hash, nil] Options to pass to stylesheet_link_tag (e.g., "data-turbo-track": "reload", omit to get current value)
      # @return [Hash, nil] The current stylesheet link options if no argument provided
      # @example Setting stylesheet link options
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     stylesheet_registry cache_strategy: :file
      #     stylesheet_link_options "data-turbo-track": "reload"
      #   end
      # @example Getting the current options
      #   MyComponent.stylesheet_link_options  # => {"data-turbo-track" => "reload"} or nil
      def stylesheet_link_options(options = nil)
        if options.nil?
          @stylesheet_link_options if defined?(@stylesheet_link_options)
        else
          @stylesheet_link_options = options
        end
      end

      public :stylesheet_link_options

      # Set or get CSS scoping strategy
      #
      # @param strategy [Symbol, nil] Scoping strategy: :selector_patching (default) or :nesting (omit to get current value)
      #   - :selector_patching: Adds [data-capsule="..."] prefix to each selector (better browser support)
      #   - :nesting: Wraps entire CSS in [data-capsule="..."] { ... } (more performant, requires CSS nesting support)
      # @return [Symbol] The current scoping strategy (default: :selector_patching)
      # @example Using CSS nesting (requires Chrome 112+, Firefox 117+, Safari 16.5+)
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     css_scoping_strategy :nesting  # More performant, no CSS parsing needed
      #
      #     def component_styles
      #       <<~CSS
      #         .section { color: red; }
      #         .heading:hover { opacity: 0.8; }
      #       CSS
      #     end
      #   end
      #   # Output: [data-capsule="abc123"] { .section { color: red; } .heading:hover { opacity: 0.8; } }
      # @example Using selector patching (default, better browser support)
      #   class MyComponent < ApplicationComponent
      #     include StyleCapsule::ViewComponent
      #     css_scoping_strategy :selector_patching  # Default
      #
      #     def component_styles
      #       <<~CSS
      #         .section { color: red; }
      #       CSS
      #     end
      #   end
      #   # Output: [data-capsule="abc123"] .section { color: red; }
      def css_scoping_strategy(strategy = nil)
        if strategy.nil?
          # Check if this class has a strategy set
          if defined?(@css_scoping_strategy) && @css_scoping_strategy
            @css_scoping_strategy
          # Otherwise, check parent class (for inheritance)
          elsif superclass.respond_to?(:css_scoping_strategy, true)
            superclass.css_scoping_strategy
          else
            :selector_patching
          end
        else
          unless [:selector_patching, :nesting].include?(strategy)
            raise ArgumentError, "css_scoping_strategy must be :selector_patching or :nesting (got: #{strategy.inspect})"
          end
          @css_scoping_strategy = strategy
        end
      end

      public :css_scoping_strategy
    end

    # Module that wraps call to add scoped wrapper
    module CallWrapper
      def call
        if component_styles?
          # Render styles first
          styles_html = render_capsule_styles

          # Get content from original call method
          content_html = super

          # Wrap content in scoped element
          scoped_wrapper = helpers.content_tag(:div, content_html.html_safe, data: {capsule: component_capsule})

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

    # Check if component should use head rendering
    #
    # Checks class-level configuration first, then allows instance override.
    def head_rendering?
      return true if self.class.head_rendering?
      false
    end

    # Scope CSS and return scoped CSS with attribute selectors
    def scope_css(css_content)
      # Use class-level cache to avoid reprocessing same CSS
      # Include capsule_id and scoping strategy in cache key
      capsule_id = component_capsule
      scoping_strategy = self.class.css_scoping_strategy
      cache_key = "#{self.class.name}:#{capsule_id}:#{scoping_strategy}"

      if self.class.css_cache.key?(cache_key)
        return self.class.css_cache[cache_key]
      end

      # Use the configured scoping strategy
      scoped_css = case scoping_strategy
      when :nesting
        CssProcessor.scope_with_nesting(css_content, capsule_id)
      else # :selector_patching (default)
        CssProcessor.scope_selectors(css_content, capsule_id)
      end

      # Cache at class level (one style block per component type/scope/strategy combination)
      self.class.css_cache[cache_key] = scoped_css

      scoped_css
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
