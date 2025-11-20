# frozen_string_literal: true

require "active_support/current_attributes"

module StyleCapsule
  # Hybrid registry for stylesheet files that need to be injected into <head>
  #
  # Uses a process-wide manifest for static file paths (like Propshaft) and request-scoped
  # storage for inline CSS. This approach:
  # - Collects static file paths once per process (no rebuilding on each request)
  # - Stores inline CSS per-request (since it's component-specific)
  # - Works correctly with both threaded and forked web servers (Puma, Unicorn, etc.)
  #
  # Supports namespaces for separation of stylesheets (e.g., "admin", "user", "public").
  #
  # @example Usage in a component with head injection
  #   class MyComponent < ApplicationComponent
  #     include StyleCapsule::Component
  #     head_injection!  # Enable head injection
  #
  #     def component_styles
  #       <<~CSS
  #         .section { color: red; }
  #       CSS
  #     end
  #   end
  #
  # @example Register a stylesheet file manually (default namespace)
  #   StyleCapsule::StylesheetRegistry.register('stylesheets/my_component')
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
  class StylesheetRegistry < ActiveSupport::CurrentAttributes
    # Default namespace for backward compatibility
    DEFAULT_NAMESPACE = :default

    # Process-wide manifest for static file paths (like Propshaft)
    # Organized by namespace: { namespace => Set of {file_path, options} hashes }
    @manifest = {} # rubocop:disable Style/ClassVars

    # Process-wide cache for inline CSS (with expiration support)
    # Structure: { cache_key => { css_content: String, cached_at: Time, expires_at: Time } }
    @inline_cache = {} # rubocop:disable Style/ClassVars

    # Track last cleanup time for lazy cleanup (prevents excessive cleanup calls)
    @last_cleanup_time = nil # rubocop:disable Style/ClassVars

    # Request-scoped storage for inline CSS only
    attribute :inline_stylesheets

    class << self
      attr_reader :manifest, :inline_cache
    end

    # Normalize namespace (nil/blank becomes DEFAULT_NAMESPACE)
    #
    # @param namespace [Symbol, String, nil] Namespace identifier
    # @return [Symbol] Normalized namespace
    def self.normalize_namespace(namespace)
      return DEFAULT_NAMESPACE if namespace.nil? || namespace.to_s.strip.empty?
      namespace.to_sym
    end

    # Register a stylesheet file path for head injection
    #
    # Static file paths are stored in process-wide manifest (collected once per process).
    # This is similar to Propshaft's manifest approach - files are static, so we can
    # collect them process-wide without rebuilding on each request.
    #
    # Files registered here are served through Rails asset pipeline (via stylesheet_link_tag).
    # This includes both:
    # - Pre-built files from assets:precompile (already in asset pipeline)
    # - Dynamically written files (written during runtime, also served through asset pipeline)
    #
    # The Set automatically deduplicates entries, so registering the same file multiple times
    # (e.g., when the same component renders multiple times) is safe and efficient.
    #
    # @param file_path [String] Path to stylesheet (relative to app/assets/stylesheets)
    # @param namespace [Symbol, String, nil] Optional namespace for separation (nil/blank uses default)
    # @param options [Hash] Options for stylesheet_link_tag
    # @return [void]
    def self.register(file_path, namespace: nil, **options)
      ns = normalize_namespace(namespace)
      @manifest[ns] ||= Set.new
      # Use a hash with file_path and options as the key to avoid duplicates
      # Set will automatically deduplicate based on hash equality
      entry = {file_path: file_path, options: options}
      @manifest[ns] << entry
    end

    # Register inline CSS for head injection
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
    # @param cache_ttl [Integer, nil] Time-to-live in seconds (for :time strategy)
    # @param cache_proc [Proc, nil] Custom cache proc (for :proc strategy)
    #   Proc receives: (css_content, capsule_id, namespace) and should return [cache_key, should_cache, expires_at]
    # @param component_class [Class, nil] Component class (for :file strategy)
    # @param stylesheet_link_options [Hash, nil] Options for stylesheet_link_tag (for :file strategy)
    # @return [void]
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
          # The Set in @manifest will deduplicate if the same file is registered multiple times
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

      # Store in request-scoped registry
      registry = instance.inline_stylesheets || {}
      registry[ns] ||= []
      registry[ns] << {
        type: :inline,
        css_content: final_css,
        capsule_id: capsule_id
      }
      instance.inline_stylesheets = registry

      # Cache the CSS if strategy is enabled and not already cached
      if cache_strategy != :none && cache_key && !cached_css && cache_strategy != :file
        cache_inline_css(cache_key, css_content, cache_strategy: cache_strategy, cache_ttl: cache_ttl, cache_proc: cache_proc, capsule_id: capsule_id, namespace: ns)
      end
    end

    # Get cached inline CSS if available and not expired
    #
    # Automatically performs lazy cleanup of expired entries if it's been more than
    # 5 minutes since the last cleanup to prevent memory leaks in long-running processes.
    #
    # @param cache_key [String] Cache key to look up
    # @param cache_strategy [Symbol] Cache strategy
    # @param cache_ttl [Integer, nil] Time-to-live in seconds
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
        return nil if cache_ttl && cached_entry[:expires_at] && Time.current > cached_entry[:expires_at]
      when :proc
        return nil unless cache_proc
        # Proc should validate cache entry
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
    # @param cache_ttl [Integer, nil] Time-to-live in seconds
    # @param cache_proc [Proc, nil] Custom cache proc
    # @param capsule_id [String, nil] Capsule ID
    # @param namespace [Symbol] Namespace
    # @return [void]
    def self.cache_inline_css(cache_key, css_content, cache_strategy:, cache_ttl: nil, cache_proc: nil, capsule_id: nil, namespace: nil)
      expires_at = nil

      case cache_strategy
      when :time
        expires_at = cache_ttl ? Time.current + cache_ttl : nil
      when :proc
        if cache_proc
          _key, _should_cache, proc_expires = cache_proc.call(css_content, capsule_id, namespace)
          expires_at = proc_expires
        end
      end

      @inline_cache[cache_key] = {
        css_content: css_content,
        cached_at: Time.current,
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

      current_time = Time.current
      expired_keys = []

      @inline_cache.each do |cache_key, entry|
        # Remove entries that have an expires_at time and it's in the past
        if entry[:expires_at] && current_time > entry[:expires_at]
          expired_keys << cache_key
        end
      end

      expired_keys.each { |key| @inline_cache.delete(key) }
      @last_cleanup_time = current_time

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

      if @last_cleanup_time.nil? || (Time.current - @last_cleanup_time) > cleanup_interval
        cleanup_expired_cache
      end
    end

    private_class_method :cleanup_expired_cache_if_needed

    # Get all registered file paths from process-wide manifest (organized by namespace)
    #
    # @return [Hash<Symbol, Set<Hash>>] Hash of namespace => set of file registrations
    def self.manifest_files
      @manifest.dup
    end

    # Get all registered inline stylesheets for current request (organized by namespace)
    #
    # @return [Hash<Symbol, Array<Hash>>] Hash of namespace => array of inline stylesheet registrations
    def self.request_inline_stylesheets
      instance.inline_stylesheets || {}
    end

    # Get all stylesheets (files + inline) for a specific namespace
    #
    # @param namespace [Symbol, String, nil] Namespace identifier (nil/blank uses default)
    # @return [Array<Hash>] Array of stylesheet registrations for the namespace
    def self.stylesheets_for(namespace: nil)
      ns = normalize_namespace(namespace)
      result = []

      # Add process-wide file paths
      if @manifest[ns]
        result.concat(@manifest[ns].to_a)
      end

      # Add request-scoped inline CSS
      inline = request_inline_stylesheets[ns] || []
      result.concat(inline)

      result
    end

    # Clear request-scoped inline stylesheets (does not clear process-wide manifest)
    #
    # @param namespace [Symbol, String, nil] Optional namespace to clear (nil clears all)
    # @return [void]
    def self.clear(namespace: nil)
      if namespace.nil?
        instance.inline_stylesheets = {}
      else
        ns = normalize_namespace(namespace)
        registry = instance.inline_stylesheets || {}
        registry.delete(ns)
        instance.inline_stylesheets = registry
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
    # Combines process-wide file manifest with request-scoped inline CSS.
    # Automatically clears request-scoped inline CSS after rendering (manifest persists).
    #
    # @param view_context [ActionView::Base, nil] The view context (for helpers like content_tag, stylesheet_link_tag)
    #   In ERB: pass `self` (the view context)
    #   In Phlex: pass `view_context` method
    #   If nil, falls back to basic HTML generation
    # @param namespace [Symbol, String, nil] Optional namespace to render (nil/blank renders all namespaces)
    # @return [String] HTML-safe string with stylesheet tags
    def self.render_head_stylesheets(view_context = nil, namespace: nil)
      if namespace.nil? || namespace.to_s.strip.empty?
        # Render all namespaces
        all_stylesheets = []

        # Collect from process-wide manifest (all namespaces)
        @manifest.each do |ns, files|
          all_stylesheets.concat(files.to_a)
        end

        # Collect from request-scoped inline CSS (all namespaces)
        request_inline_stylesheets.each do |_ns, inline|
          all_stylesheets.concat(inline)
        end

        clear # Clear request-scoped inline CSS only
        return "".html_safe if all_stylesheets.empty?

        all_stylesheets.map do |stylesheet|
          if stylesheet[:type] == :inline
            render_inline_stylesheet(stylesheet, view_context)
          else
            render_file_stylesheet(stylesheet, view_context)
          end
        end.join("\n").html_safe

      else
        # Render specific namespace
        ns = normalize_namespace(namespace)
        stylesheets = stylesheets_for(namespace: ns).dup
        clear(namespace: ns) # Clear request-scoped inline CSS only

        return "".html_safe if stylesheets.empty?

        stylesheets.map do |stylesheet|
          if stylesheet[:type] == :inline
            render_inline_stylesheet(stylesheet, view_context)
          else
            render_file_stylesheet(stylesheet, view_context)
          end
        end.join("\n").html_safe

      end
    end

    # Check if there are any registered stylesheets
    #
    # @param namespace [Symbol, String, nil] Optional namespace to check (nil checks all)
    # @return [Boolean]
    def self.any?(namespace: nil)
      if namespace.nil?
        # Check process-wide manifest
        has_files = !@manifest.empty? && @manifest.values.any? { |files| !files.empty? }
        # Check request-scoped inline CSS
        inline = request_inline_stylesheets
        has_inline = !inline.empty? && inline.values.any? { |stylesheets| !stylesheets.empty? }
        has_files || has_inline
      else
        ns = normalize_namespace(namespace)
        # Check process-wide manifest
        has_files = @manifest[ns] && !@manifest[ns].empty?
        # Check request-scoped inline CSS
        has_inline = request_inline_stylesheets[ns] && !request_inline_stylesheets[ns].empty?
        !!(has_files || has_inline)
      end
    end

    # Render a file-based stylesheet
    def self.render_file_stylesheet(stylesheet, view_context)
      file_path = stylesheet[:file_path]
      options = stylesheet[:options] || {}

      if view_context&.respond_to?(:stylesheet_link_tag)
        view_context.stylesheet_link_tag(file_path, **options)
      else
        # Fallback if no view context
        href = "/assets/#{file_path}.css"
        tag_options = options.map { |k, v| %(#{k}="#{v}") }.join(" ")
        %(<link rel="stylesheet" href="#{href}"#{" #{tag_options}" unless tag_options.empty?}>).html_safe
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
      %(<style type="text/css">#{css_content}</style>).html_safe
    end

    private_class_method :render_file_stylesheet, :render_inline_stylesheet
  end
end
