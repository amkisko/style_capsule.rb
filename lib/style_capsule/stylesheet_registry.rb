# frozen_string_literal: true

require_relative "instrumentation"
require_relative "asset_path"

module StyleCapsule
  # Helper to determine the parent class for StylesheetRegistry
  # ActiveSupport::CurrentAttributes is optional - if ActiveSupport is loaded,
  # it will be available. Otherwise, we fall back to Object.
  #
  # This is evaluated at class definition time, so it can't be stubbed.
  # For testing fallback paths, use the instance methods that check availability.
  def self.stylesheet_registry_parent_class
    defined?(ActiveSupport::CurrentAttributes) ? ActiveSupport::CurrentAttributes : Object
  end

  # Hybrid registry for stylesheet files that need to be injected into <head>
  #
  # Uses a process-wide manifest for eager registrations, request-scoped storage for
  # render-time file paths and inline CSS, and optional Rack middleware to inject
  # stylesheets registered during body rendering into +<head>+ on the same request.
  #
  # This approach:
  # - Keeps eager file paths in a process-wide manifest (class load / boot time)
  # - Stores render-time file paths and inline CSS per request
  # - Works correctly with both threaded and forked web servers (Puma, Unicorn, etc.)
  #
  # Supports namespaces for separation of stylesheets (e.g., "admin", "user", "public").
  #
  # @example Usage in a component with head rendering
  #   class MyComponent < ApplicationComponent
  #     include StyleCapsule::Component
  #     stylesheet_registry  # Enable head rendering
  #
  #     def component_styles
  #       <<~CSS
  #         .section { color: red; }
  #       CSS
  #     end
  #   end
  #
  # @example Register a stylesheet during rendering (request-scoped)
  #   StyleCapsule::StylesheetRegistry.register('stylesheets/my_component')
  #
  # @example Register a stylesheet eagerly at boot or class load (process-wide manifest)
  #   StyleCapsule::StylesheetRegistry.register_eager('stylesheets/my_component', namespace: :user)
  #
  # @example Register a stylesheet with a namespace
  #   StyleCapsule::StylesheetRegistry.register('stylesheets/admin/dashboard', namespace: :admin)
  #
  # @example Usage in layout (ERB) - render all namespaces
  #   # In app/views/layouts/application.html.erb
  #   <head>
  #     <%= StyleCapsule::StylesheetRegistry.render_head_stylesheets(self) %>
  #   </head>
  #
  # @example Usage in layout (ERB) - render specific namespace
  #   <head>
  #     <%= StyleCapsule::StylesheetRegistry.render_head_stylesheets(self, namespace: :admin) %>
  #   </head>
  #
  # @example Usage in layout (Phlex)
  #   # In app/views/layouts/application_layout.rb
  #   def view_template(&block)
  #     html do
  #       head do
  #         raw StyleCapsule::StylesheetRegistry.render_head_stylesheets(view_context)
  #       end
  #       body(&block)
  #     end
  #   end
  class StylesheetRegistry < StyleCapsule.stylesheet_registry_parent_class
    # Default namespace for backward compatibility
    DEFAULT_NAMESPACE = :default

    # Process-wide manifest for static file paths (like Propshaft)
    # Organized by namespace: { namespace => { logical_path => { file_path:, options: } } }
    @manifest = {} # rubocop:disable Style/ClassVars, ThreadSafety/MutableClassInstanceVariable

    # Process-wide cache for inline CSS (with expiration support)
    # Structure: { cache_key => { css_content: String, cached_at: Time, expires_at: Time } }
    @inline_cache = {} # rubocop:disable Style/ClassVars, ThreadSafety/MutableClassInstanceVariable

    # Track last cleanup time for lazy cleanup (prevents excessive cleanup calls)
    @last_cleanup_time = nil # rubocop:disable Style/ClassVars

    # Request-scoped storage for inline CSS and render-time file registrations
    # Only define attribute if we're inheriting from CurrentAttributes
    if defined?(ActiveSupport::CurrentAttributes) && self < ActiveSupport::CurrentAttributes
      attribute :inline_stylesheets
      attribute :request_file_stylesheets
    end

    class << self
      attr_reader :manifest, :inline_cache

      # Get current time (ActiveSupport::Time.current or Time.now fallback)
      def current_time
        if defined?(Time) && Time.respond_to?(:current)
          Time.current
        else
          # rubocop:disable Rails/TimeZone
          # Time.now is intentional fallback for non-Rails usage when Time.current is unavailable
          Time.now
          # rubocop:enable Rails/TimeZone
        end
      end

      # Check if we're using ActiveSupport::CurrentAttributes
      # This method can be stubbed in tests to test fallback paths
      def using_current_attributes?
        defined?(ActiveSupport::CurrentAttributes) && self < ActiveSupport::CurrentAttributes
      end

      # Get inline stylesheets (thread-local fallback if not using CurrentAttributes)
      def inline_stylesheets
        if using_current_attributes?
          # When using CurrentAttributes, access the instance attribute
          # CurrentAttributes automatically provides access to instance attributes
          inst = instance
          inst&.inline_stylesheets || {}
        else
          Thread.current[:style_capsule_inline_stylesheets] ||= {}
        end
      end

      # Set inline stylesheets (thread-local fallback if not using CurrentAttributes)
      def inline_stylesheets=(value)
        if using_current_attributes?
          # When using CurrentAttributes, set via the instance
          inst = instance
          inst.inline_stylesheets = value if inst
        else
          Thread.current[:style_capsule_inline_stylesheets] = value
        end
      end

      # Get request-scoped file stylesheets (thread-local fallback if not using CurrentAttributes)
      def request_file_stylesheets
        if using_current_attributes?
          inst = instance
          inst&.request_file_stylesheets || {}
        else
          Thread.current[:style_capsule_request_file_stylesheets] ||= {}
        end
      end

      # Set request-scoped file stylesheets (thread-local fallback if not using CurrentAttributes)
      def request_file_stylesheets=(value)
        if using_current_attributes?
          inst = instance
          inst.request_file_stylesheets = value if inst
        else
          Thread.current[:style_capsule_request_file_stylesheets] = value
        end
      end

      # Get instance (for CurrentAttributes compatibility)
      def instance
        if using_current_attributes?
          # Call the CurrentAttributes instance method from parent class
          super
        else
          # Return a simple object that responds to request-scoped attributes
          # This is mainly for compatibility with code that might call instance.inline_stylesheets
          registry_class = self
          @_standalone_instance ||= begin
            obj = Object.new
            obj.define_singleton_method(:inline_stylesheets) { registry_class.inline_stylesheets }
            obj.define_singleton_method(:inline_stylesheets=) { |v| registry_class.inline_stylesheets = v }
            obj.define_singleton_method(:request_file_stylesheets) { registry_class.request_file_stylesheets }
            obj.define_singleton_method(:request_file_stylesheets=) { |v| registry_class.request_file_stylesheets = v }
            obj
          end
        end
      end

      private
    end

    # Normalize namespace (nil/blank becomes DEFAULT_NAMESPACE)
    #
    # @param namespace [Symbol, String, nil] Namespace identifier
    # @return [Symbol] Normalized namespace
    def self.normalize_namespace(namespace)
      return DEFAULT_NAMESPACE if namespace.nil? || namespace.to_s.strip.empty?
      namespace.to_sym
    end

    # Register a stylesheet file path during rendering (request-scoped).
    #
    # Render-time registrations are stored per request and emitted by
    # +render_head_stylesheets+ when the layout head runs before the body, or by
    # +HeadInjectionMiddleware+ when components register stylesheets later in the response.
    #
    # Files registered here are served through Rails asset pipeline (via stylesheet_link_tag).
    #
    # @param file_path [String] Path to stylesheet (relative to app/assets/stylesheets)
    # @param namespace [Symbol, String, nil] Optional namespace for separation (nil/blank uses default)
    # @param options [Hash] Options for stylesheet_link_tag
    # @return [void]
    def self.register(file_path, namespace: nil, **options)
      register_request_file(file_path, namespace: namespace, **options)
    end

    # Register a stylesheet file path eagerly (process-wide manifest).
    #
    # Use at class load or boot time when the stylesheet should always be available in
    # +render_head_stylesheets+ without waiting for a component render.
    #
    # @param file_path [String] Path to stylesheet (relative to app/assets/stylesheets)
    # @param namespace [Symbol, String, nil] Optional namespace for separation (nil/blank uses default)
    # @param options [Hash] Options for stylesheet_link_tag
    # @return [void]
    def self.register_eager(file_path, namespace: nil, **options)
      ns = normalize_namespace(namespace)
      path = AssetPath.validate_logical_path!(file_path)

      Instrumentation.instrument_registration(
        namespace: ns,
        file_path: path,
        inline_size: nil,
        cache_strategy: :none
      ) do
        @manifest[ns] ||= {}
        @manifest[ns][path] = {file_path: path, options: options}
      end
    end

    # @api private
    def self.register_request_file(file_path, namespace: nil, **options)
      ns = normalize_namespace(namespace)
      path = AssetPath.validate_logical_path!(file_path)

      Instrumentation.instrument_registration(
        namespace: ns,
        file_path: path,
        inline_size: nil,
        cache_strategy: :none
      ) do
        registry = request_file_stylesheets
        registry[ns] ||= {}
        registry[ns][path] = {file_path: path, options: options}
        self.request_file_stylesheets = registry
      end
    end
    private_class_method :register_request_file

    # Register inline CSS for head rendering
    #
    # Inline CSS can be cached based on cache configuration. Supports:
    # - No caching (default): stored per-request
    # - Time-based caching: cache expires after TTL
    # - Custom proc caching: use proc to determine cache key and validity
    # - File-based caching: writes CSS to files for HTTP caching
    #
    # @param css_content [String] CSS content (should already be scoped)
    # @param namespace [Symbol, String, nil] Optional namespace for separation (nil/blank uses default)
    # @param capsule_id [String, nil] Optional capsule ID for reference
    # @param cache_key [String, nil] Optional cache key (for cache lookup)
    # @param cache_strategy [Symbol, nil] Cache strategy: :none, :time, :proc, :file (default: :none)
    # @param cache_ttl [Integer, ActiveSupport::Duration, nil] Time-to-live in seconds (for :time strategy). Supports ActiveSupport::Duration (e.g., 1.hour, 30.minutes)
    # @param cache_proc [Proc, nil] Custom cache proc (for :proc strategy)
    #   Proc receives: (css_content, capsule_id, namespace) and should return [cache_key, should_cache, expires_at]
    # @param component_class [Class, nil] Component class (for :file strategy)
    # @param stylesheet_link_options [Hash, nil] Options for stylesheet_link_tag (for :file strategy)
    # @return [void]
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- coordinates file, inline, and cache registration
    def self.register_inline(css_content, namespace: nil, capsule_id: nil, cache_key: nil, cache_strategy: :none, cache_ttl: nil, cache_proc: nil, component_class: nil, stylesheet_link_options: nil)
      ns = normalize_namespace(namespace)

      # Handle file-based caching (writes to file and registers as file path)
      if cache_strategy == :file && component_class && capsule_id
        # Check if file already exists (from precompilation via assets:precompile or previous write)
        # Pre-built files are already available through Rails asset pipeline and just need to be registered
        existing_path = CssFileWriter.file_path_for(
          component_class: component_class,
          capsule_id: capsule_id
        )

        if existing_path
          # File exists (pre-built or previously written), register it as a file path
          # The manifest deduplicates by logical path if the same file is registered multiple times
          # This file will be served through Rails asset pipeline (stylesheet_link_tag)
          link_options = stylesheet_link_options || {}
          register(existing_path, namespace: namespace, **link_options)
          return
        end

        # File doesn't exist, write it dynamically (development mode or first render)
        # After writing, register it as a file path so it's served as an asset
        file_path = CssFileWriter.write_css(
          css_content: css_content,
          component_class: component_class,
          capsule_id: capsule_id
        )

        if file_path
          # Register as file path instead of inline CSS
          # This ensures the file is served through Rails asset pipeline
          link_options = stylesheet_link_options || {}
          register(file_path, namespace: namespace, **link_options)
          return
        end
      end

      # Check cache if strategy is enabled
      cached_css = nil
      if cache_strategy != :none && cache_key && cache_strategy != :file
        cached_css = cached_inline(cache_key, cache_strategy: cache_strategy, cache_ttl: cache_ttl, cache_proc: cache_proc, css_content: css_content, capsule_id: capsule_id, namespace: ns)
      end

      # Use cached CSS if available, otherwise use provided CSS
      final_css = cached_css || css_content

      Instrumentation.instrument_registration(
        namespace: ns,
        file_path: nil,
        inline_size: final_css.bytesize,
        cache_strategy: cache_strategy
      ) do
        registry = inline_stylesheets
        registry[ns] ||= []
        registry[ns] << {
          type: :inline,
          css_content: final_css,
          capsule_id: capsule_id
        }
        self.inline_stylesheets = registry
      end

      # Cache the CSS if strategy is enabled and not already cached
      if cache_strategy != :none && cache_key && !cached_css && cache_strategy != :file
        cache_inline_css(cache_key, css_content, cache_strategy: cache_strategy, cache_ttl: cache_ttl, cache_proc: cache_proc, capsule_id: capsule_id, namespace: ns)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Get cached inline CSS if available and not expired
    #
    # Automatically performs lazy cleanup of expired entries if it's been more than
    # 5 minutes since the last cleanup to prevent memory leaks in long-running processes.
    #
    # @param cache_key [String] Cache key to look up
    # @param cache_strategy [Symbol] Cache strategy
    # @param cache_ttl [Integer, ActiveSupport::Duration, nil] Time-to-live in seconds. Supports ActiveSupport::Duration (e.g., 1.hour, 30.minutes)
    # @param cache_proc [Proc, nil] Custom cache proc
    # @param css_content [String] Original CSS content (for proc strategy)
    # @param capsule_id [String, nil] Capsule ID (for proc strategy)
    # @param namespace [Symbol] Namespace (for proc strategy)
    # @return [String, nil] Cached CSS content or nil if not cached/expired
    def self.cached_inline(cache_key, cache_strategy:, cache_ttl: nil, cache_proc: nil, css_content: nil, capsule_id: nil, namespace: nil)
      # Lazy cleanup: remove expired entries if it's been a while (every 5 minutes)
      # This prevents memory leaks in long-running processes without impacting performance
      cleanup_expired_cache_if_needed

      cached_entry = @inline_cache[cache_key]
      return nil unless cached_entry

      # Check expiration based on strategy
      case cache_strategy
      when :time
        return nil if cache_ttl && cached_entry[:expires_at] && current_time > cached_entry[:expires_at]
      when :proc
        return nil unless cache_proc
        # Re-validation: the proc is invoked on every read with the *current* request's CSS.
        # Return [_, true, _] from the proc to keep using the cached entry; false invalidates it.
        # (This is closer to a conditional cache than a blind key/value store.)
        _key, should_use, _expires = cache_proc.call(css_content, capsule_id, namespace)
        return nil unless should_use
      end

      cached_entry[:css_content]
    end

    # Cache inline CSS with expiration
    #
    # @param cache_key [String] Cache key
    # @param css_content [String] CSS content to cache
    # @param cache_strategy [Symbol] Cache strategy
    # @param cache_ttl [Integer, ActiveSupport::Duration, nil] Time-to-live in seconds. Supports ActiveSupport::Duration (e.g., 1.hour, 30.minutes)
    # @param cache_proc [Proc, nil] Custom cache proc
    # @param capsule_id [String, nil] Capsule ID
    # @param namespace [Symbol] Namespace
    # @return [void]
    def self.cache_inline_css(cache_key, css_content, cache_strategy:, cache_ttl: nil, cache_proc: nil, capsule_id: nil, namespace: nil)
      expires_at = nil

      case cache_strategy
      when :time
        # Handle ActiveSupport::Duration (e.g., 1.hour) or integer seconds
        ttl_seconds = if cache_ttl.respond_to?(:to_i)
          cache_ttl.to_i
        else
          cache_ttl
        end
        expires_at = ttl_seconds ? current_time + ttl_seconds : nil
      when :proc
        if cache_proc
          _key, _should_cache, proc_expires = cache_proc.call(css_content, capsule_id, namespace)
          expires_at = proc_expires
        end
      end

      @inline_cache[cache_key] = {
        css_content: css_content,
        cached_at: current_time,
        expires_at: expires_at
      }
    end

    # Clear inline CSS cache
    #
    # @param cache_key [String, nil] Specific cache key to clear (nil clears all)
    # @return [void]
    def self.clear_inline_cache(cache_key = nil)
      if cache_key
        @inline_cache.delete(cache_key)
      else
        @inline_cache.clear
      end
    end

    # Clean up expired entries from the inline CSS cache
    #
    # Removes all cache entries that have expired (where expires_at is set and
    # Time.current > expires_at). This prevents memory leaks in long-running processes.
    #
    # This method is called automatically by cached_inline (lazy cleanup every 5 minutes),
    # but can also be called manually for explicit cleanup (e.g., from a background job
    # or scheduled task).
    #
    # @return [Integer] Number of expired entries removed
    # @example Manual cleanup
    #   StyleCapsule::StylesheetRegistry.cleanup_expired_cache
    # @example Scheduled cleanup (e.g., in a background job)
    #   # In a scheduled job or initializer
    #   StyleCapsule::StylesheetRegistry.cleanup_expired_cache
    def self.cleanup_expired_cache
      return 0 if @inline_cache.empty?

      now = current_time
      expired_keys = []

      @inline_cache.each do |cache_key, entry|
        # Remove entries that have an expires_at time and it's in the past
        if entry[:expires_at] && now > entry[:expires_at]
          expired_keys << cache_key
        end
      end

      expired_keys.each { |key| @inline_cache.delete(key) }
      @last_cleanup_time = now

      expired_keys.size
    end

    # Check if cleanup is needed and perform it if so
    #
    # Only performs cleanup if it's been more than 5 minutes since the last cleanup.
    # This prevents excessive cleanup calls while still preventing memory leaks.
    #
    # @return [void]
    # @api private
    def self.cleanup_expired_cache_if_needed
      # Cleanup every 5 minutes (300 seconds) to balance memory usage and performance
      cleanup_interval = 300

      if @last_cleanup_time.nil? || (current_time - @last_cleanup_time) > cleanup_interval
        cleanup_expired_cache
      end
    end

    private_class_method :cleanup_expired_cache_if_needed

    # Get all registered file paths from process-wide manifest (organized by namespace)
    #
    # @return [Hash<Symbol, Array<Hash>>] Hash of namespace => array of file registrations
    def self.manifest_files
      @manifest.transform_values { |h| h.values }
    end

    # Get all registered inline stylesheets for current request (organized by namespace)
    #
    # @return [Hash<Symbol, Array<Hash>>] Hash of namespace => array of inline stylesheet registrations
    def self.request_inline_stylesheets
      inline_stylesheets
    end

    # Get all request-scoped file stylesheets for the current request (organized by namespace)
    #
    # @return [Hash<Symbol, Hash<String, Hash>>] Hash of namespace => logical path => registration
    def self.request_stylesheet_files
      request_file_stylesheets
    end

    # Get all stylesheets (files + inline) for a specific namespace
    #
    # @param namespace [Symbol, String, nil] Namespace identifier (nil/blank uses default)
    # @return [Array<Hash>] Array of stylesheet registrations for the namespace
    def self.stylesheets_for(namespace: nil)
      ns = normalize_namespace(namespace)
      result = merged_file_registrations_for_namespace(ns)

      inline = request_inline_stylesheets[ns] || []
      result.concat(inline)

      result
    end

    # Whether request-scoped stylesheets remain to inject into +<head>+
    #
    # @return [Boolean]
    def self.pending_head_stylesheets?
      !pending_request_stylesheets.empty?
    end

    # Clear request-scoped inline CSS and render-time file registrations (does not clear process-wide manifest)
    #
    # @param namespace [Symbol, String, nil] Optional namespace to clear (nil clears all)
    # @return [void]
    def self.clear(namespace: nil)
      if namespace.nil?
        self.inline_stylesheets = {}
        self.request_file_stylesheets = {}
      else
        ns = normalize_namespace(namespace)
        inline_registry = inline_stylesheets
        inline_registry.delete(ns)
        self.inline_stylesheets = inline_registry

        file_registry = request_file_stylesheets
        file_registry.delete(ns)
        self.request_file_stylesheets = file_registry
      end
    end

    # Clear process-wide manifest (useful for testing or development reloading)
    #
    # @param namespace [Symbol, String, nil] Optional namespace to clear (nil clears all)
    # @return [void]
    def self.clear_manifest(namespace: nil)
      if namespace.nil?
        @manifest = {}
      else
        ns = normalize_namespace(namespace)
        @manifest.delete(ns)
      end
    end

    # Render registered stylesheets as HTML
    #
    # This should be called in the layout's <head> section.
    # Combines eager manifest files with request-scoped file paths and inline CSS
    # registered before this call. Stylesheets registered later in the response are
    # injected into +<head>+ by +HeadInjectionMiddleware+ when enabled.
    #
    # Automatically clears request-scoped inline CSS and file paths after rendering
    # for the selected namespace(s). The eager manifest persists.
    #
    # @param view_context [ActionView::Base, nil] The view context (for helpers like content_tag, stylesheet_link_tag)
    #   In ERB: pass `self` (the view context)
    #   In Phlex: pass `view_context` method
    #   If nil, falls back to basic HTML generation
    # @param namespace [Symbol, String, nil] Optional namespace to render (nil/blank renders all namespaces)
    # @return [String] HTML-safe string with stylesheet tags
    # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity -- renders mixed inline and file registrations
    def self.render_head_stylesheets(view_context = nil, namespace: nil)
      if namespace.nil? || namespace.to_s.strip.empty?
        all_stylesheets = merged_file_registrations_all_namespaces

        request_inline_stylesheets.each do |_ns, inline|
          all_stylesheets.concat(inline)
        end

        clear # Clear request-scoped inline CSS and file paths only
        return safe_string("") if all_stylesheets.empty?

        all_stylesheets.map do |stylesheet|
          if stylesheet[:type] == :inline
            render_inline_stylesheet(stylesheet, view_context)
          else
            render_file_stylesheet(stylesheet, view_context)
          end
        end.join("\n").then { |s| safe_string(s) }

      else
        # Render specific namespace
        ns = normalize_namespace(namespace)
        stylesheets = stylesheets_for(namespace: ns).dup
        clear(namespace: ns) # Clear request-scoped inline CSS and file paths only

        return safe_string("") if stylesheets.empty?

        stylesheets.map do |stylesheet|
          if stylesheet[:type] == :inline
            render_inline_stylesheet(stylesheet, view_context)
          else
            render_file_stylesheet(stylesheet, view_context)
          end
        end.join("\n").then { |s| safe_string(s) }

      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/PerceivedComplexity

    # Check if there are any registered stylesheets
    #
    # @param namespace [Symbol, String, nil] Optional namespace to check (nil checks all)
    # @return [Boolean]
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- checks manifest and request-scoped registries
    def self.any?(namespace: nil)
      if namespace.nil?
        # Check process-wide manifest
        has_files = !@manifest.empty? && @manifest.values.any? { |files| !files.empty? }
        # Check request-scoped file paths
        request_files = request_file_stylesheets
        has_request_files = !request_files.empty? && request_files.values.any? { |files| !files.empty? }
        # Check request-scoped inline CSS
        inline = request_inline_stylesheets
        has_inline = !inline.empty? && inline.values.any? { |stylesheets| !stylesheets.empty? }
        has_files || has_request_files || has_inline
      else
        ns = normalize_namespace(namespace)
        # Check process-wide manifest
        has_files = @manifest[ns] && !@manifest[ns].empty?
        # Check request-scoped file paths
        has_request_files = request_file_stylesheets[ns] && !request_file_stylesheets[ns].empty?
        # Check request-scoped inline CSS
        has_inline = request_inline_stylesheets[ns] && !request_inline_stylesheets[ns].empty?
        !!(has_files || has_request_files || has_inline)
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Inject pending request-scoped stylesheets into an HTML document before +</head>+.
    #
    # Used by +HeadInjectionMiddleware+ after the body has rendered and components have
    # called +register_stylesheet+ or +register_inline+.
    #
    # @param html [String] Full HTML response body
    # @param view_context [ActionView::Base, nil] View context for +stylesheet_link_tag+
    # @return [String] HTML with pending stylesheet tags injected, or the original HTML
    def self.inject_pending_head_stylesheets(html, view_context = nil)
      pending_stylesheets = pending_request_stylesheets
      return html if pending_stylesheets.empty?

      closing_head_index = html.match(%r{</head>}i)&.begin(0)
      return html unless closing_head_index

      tags = render_stylesheet_tags(pending_stylesheets, view_context)
      return html if tags.empty?

      injected = html.dup
      injected.insert(closing_head_index, "#{tags}\n")
      clear
      injected
    end

    # @api private
    def self.merged_file_registrations_for_namespace(namespace)
      merge_file_registrations(@manifest[namespace], request_file_stylesheets[namespace])
    end

    # @api private
    def self.merged_file_registrations_all_namespaces
      merged = {}

      @manifest.each do |ns, files|
        files.each_value do |entry|
          merged[[ns, entry[:file_path]]] = entry
        end
      end

      request_file_stylesheets.each do |ns, files|
        files.each_value do |entry|
          merged[[ns, entry[:file_path]]] = entry
        end
      end

      merged.values
    end

    # @api private
    def self.merge_file_registrations(eager_files, request_files)
      merged = {}
      eager_files&.each_value { |entry| merged[entry[:file_path]] = entry }
      request_files&.each_value { |entry| merged[entry[:file_path]] = entry }
      merged.values
    end

    # @api private
    def self.pending_request_stylesheets
      stylesheets = []

      request_file_stylesheets.each_value do |files|
        stylesheets.concat(files.values)
      end

      request_inline_stylesheets.each_value do |inline_styles|
        stylesheets.concat(inline_styles)
      end

      stylesheets
    end

    # @api private
    def self.render_stylesheet_tags(stylesheets, view_context)
      return safe_string("") if stylesheets.empty?

      stylesheets.map do |stylesheet|
        if stylesheet[:type] == :inline
          render_inline_stylesheet(stylesheet, view_context)
        else
          render_file_stylesheet(stylesheet, view_context)
        end
      end.join("\n").then { |output| safe_string(output) }.to_s
    end
    private_class_method :pending_request_stylesheets, :render_stylesheet_tags,
      :merged_file_registrations_for_namespace, :merged_file_registrations_all_namespaces,
      :merge_file_registrations

    # Render a file-based stylesheet
    def self.render_file_stylesheet(stylesheet, view_context)
      file_path = stylesheet[:file_path]
      options = stylesheet[:options] || {}

      if view_context&.respond_to?(:stylesheet_link_tag)
        view_context.stylesheet_link_tag(file_path, **options)
      else
        # Fallback if no view context (logical path validated in .register)
        href = "/assets/#{file_path}.css"
        tag_options = options.map { |k, v| %(#{k}="#{v}") }.join(" ")
        safe_string(%(<link rel="stylesheet" href="#{href}"#{" #{tag_options}" unless tag_options.empty?}>))
      end
    end

    # Render an inline stylesheet
    def self.render_inline_stylesheet(stylesheet, view_context)
      # CSS content is already scoped when registered from components
      # capsule_id is stored for reference but CSS is pre-processed
      css_content = stylesheet[:css_content]

      # Construct HTML manually to avoid any HTML escaping issues
      # CSS content should not be HTML-escaped as it's inside a <style> tag
      # Using string interpolation with html_safe ensures CSS is not escaped
      safe_string(%(<style type="text/css">#{css_content}</style>))
    end

    # Make string HTML-safe (compatible with Rails and non-Rails)
    #
    # @param string [String] String to mark as safe
    # @return [String] HTML-safe string
    def self.safe_string(string)
      if string.respond_to?(:html_safe)
        string.html_safe
      else
        string
      end
    end

    private_class_method :render_file_stylesheet, :render_inline_stylesheet, :safe_string
  end
end
