# frozen_string_literal: true

module StyleCapsule
  # Shared class-level DSL for {StyleCapsule::Component} and {StyleCapsule::ViewComponent}.
  #
  # @api private
  module ComponentClassMethods
    MAX_CSS_CACHE_ENTRIES = 256

    # Class-level cache for scoped CSS per component class
    def css_cache
      @css_cache ||= {}
    end

    # Store scoped CSS in the bounded class-level cache
    #
    # @param cache_key [String]
    # @param scoped_css [String]
    # @return [String] +scoped_css+
    def store_css_cache(cache_key, scoped_css)
      cache = css_cache
      order = css_cache_order
      evict_css_cache_if_full!(cache, order)
      cache[cache_key] = scoped_css
      order << cache_key
      scoped_css
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
      @css_cache_order = []
    end

    private

    def css_cache_order
      @css_cache_order ||= []
    end

    def evict_css_cache_if_full!(cache, order)
      while order.size >= MAX_CSS_CACHE_ENTRIES
        old = order.shift
        cache.delete(old)
      end
    end

    public

    # Set or get a custom capsule ID for this component class (useful for testing)
    #
    # @param capsule_id [String, nil] The custom capsule ID to use (nil to get current value)
    # @return [String, nil] The current capsule ID if no argument provided
    # @example Setting a custom capsule ID
    #   class MyComponent < ApplicationComponent
    #     include StyleCapsule::Component
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
    # @deprecated Prefer {#style_capsule}, which configures namespace, cache, scoping, and head
    #   rendering in one place. This method remains for backward compatibility.
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

    # Check if component uses head rendering (checks instance variable, then parent class, defaults to false)
    #
    # @return [Boolean] Whether head rendering is enabled (default: false)
    def head_rendering?
      if defined?(@head_rendering)
        @head_rendering
      elsif superclass.respond_to?(:head_rendering?, true)
        superclass.head_rendering?
      else
        false
      end
    end

    public :head_rendering?

    # Get the namespace for stylesheet registry (checks instance variable, then parent class, defaults to nil)
    #
    # @return [Symbol, String, nil] The namespace identifier (default: nil)
    def stylesheet_namespace
      if defined?(@stylesheet_namespace) && @stylesheet_namespace
        @stylesheet_namespace
      elsif superclass.respond_to?(:stylesheet_namespace, true)
        superclass.stylesheet_namespace
      end
    end

    # Configure StyleCapsule settings
    #
    # All settings support class inheritance - child classes inherit settings from parent classes
    # and can override them by calling style_capsule again with different values.
    #
    # @param namespace [Symbol, String, nil] Default namespace for stylesheets
    # @param cache_strategy [Symbol, String, Proc, nil] Cache strategy: :none (default), :time, :proc, :file
    # @param cache_ttl [Integer, ActiveSupport::Duration, nil] Time-to-live in seconds (for :time strategy)
    # @param cache_proc [Proc, nil] Custom cache proc (for :proc strategy)
    # @param scoping_strategy [Symbol, nil] CSS scoping strategy: :selector_patching (default) or :nesting
    # @param head_rendering [Boolean, nil] Enable head rendering (default: true if any option is set, false otherwise)
    # @param tag [Symbol, String, nil] HTML tag name for wrapper element (default: :div)
    # @return [void]
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- DSL configures multiple optional class settings
    def style_capsule(namespace: nil, cache_strategy: nil, cache_ttl: nil, cache_proc: nil, scoping_strategy: nil, head_rendering: nil, tag: nil)
      # Set namespace (stored in instance variable, but getter checks parent class for inheritance)
      if namespace
        @stylesheet_namespace = namespace
      end

      # Configure cache strategy if provided
      if cache_strategy || cache_ttl || cache_proc
        normalized_strategy, normalized_proc = normalize_cache_strategy(cache_strategy || :none, cache_proc)
        @inline_cache_strategy = normalized_strategy
        # Explicitly set cache_ttl (even if nil) to override parent's value when cache settings are changed
        @inline_cache_ttl = cache_ttl
        @inline_cache_proc = normalized_proc
      end

      # Configure CSS scoping strategy if provided
      if scoping_strategy
        unless [:selector_patching, :nesting].include?(scoping_strategy)
          raise ArgumentError, "scoping_strategy must be :selector_patching or :nesting (got: #{scoping_strategy.inspect})"
        end
        @css_scoping_strategy = scoping_strategy
      end

      # Configure wrapper tag if provided
      if tag
        @wrapper_tag = tag
      end

      # Enable head rendering if explicitly set or if any option is provided (except scoping_strategy)
      if head_rendering.nil?
        @head_rendering = true if namespace || cache_strategy || cache_ttl || cache_proc
      else
        @head_rendering = head_rendering
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Get the custom scope ID if set (alias for capsule_id getter)
    def custom_capsule_id
      @custom_capsule_id if defined?(@custom_capsule_id)
    end

    # Get inline cache strategy (checks instance variable, then parent class, defaults to nil)
    #
    # @return [Symbol, nil] The cache strategy (default: nil)
    def inline_cache_strategy
      if defined?(@inline_cache_strategy) && @inline_cache_strategy
        @inline_cache_strategy
      elsif superclass.respond_to?(:inline_cache_strategy, true)
        superclass.inline_cache_strategy
      end
    end

    # Get inline cache TTL (checks instance variable, then parent class, defaults to nil)
    #
    # @return [Integer, ActiveSupport::Duration, nil] The cache TTL (default: nil)
    def inline_cache_ttl
      if defined?(@inline_cache_ttl)
        @inline_cache_ttl
      elsif superclass.respond_to?(:inline_cache_ttl, true)
        superclass.inline_cache_ttl
      end
    end

    # Get inline cache proc (checks instance variable, then parent class, defaults to nil)
    #
    # @return [Proc, nil] The cache proc (default: nil)
    def inline_cache_proc
      if defined?(@inline_cache_proc)
        @inline_cache_proc
      elsif superclass.respond_to?(:inline_cache_proc, true)
        superclass.inline_cache_proc
      end
    end

    public :head_rendering?, :stylesheet_namespace, :style_capsule, :custom_capsule_id, :inline_cache_strategy, :inline_cache_ttl, :inline_cache_proc

    # Get CSS scoping strategy (checks instance variable, then parent class, defaults to :selector_patching)
    #
    # @return [Symbol] The current scoping strategy (default: :selector_patching)
    def css_scoping_strategy
      if defined?(@css_scoping_strategy) && @css_scoping_strategy
        @css_scoping_strategy
      elsif superclass.respond_to?(:css_scoping_strategy, true)
        superclass.css_scoping_strategy
      else
        :selector_patching
      end
    end

    public :css_scoping_strategy

    # Get wrapper tag (checks instance variable, then parent class, defaults to :div)
    #
    # @return [Symbol, String] The wrapper tag (default: :div)
    def wrapper_tag
      if defined?(@wrapper_tag) && @wrapper_tag
        @wrapper_tag
      elsif superclass.respond_to?(:wrapper_tag, true)
        superclass.wrapper_tag
      else
        :div
      end
    end

    public :wrapper_tag

    # Set or get options for stylesheet_link_tag when using file-based caching
    #
    # @param options [Hash, nil] Options to pass to stylesheet_link_tag (e.g., "data-turbo-track": "reload", omit to get current value)
    # @return [Hash, nil] The current stylesheet link options if no argument provided
    def stylesheet_link_options(options = nil)
      if options.nil?
        @stylesheet_link_options if defined?(@stylesheet_link_options)
      else
        @stylesheet_link_options = options
      end
    end

    public :stylesheet_link_options
  end
end
