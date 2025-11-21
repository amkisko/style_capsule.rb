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

module StyleCapsule
  # ERB Helper module for use in Rails views
  #
  # This module is automatically included in ActionView::Base via Railtie.
  # No manual inclusion is required - helpers are available in all ERB templates.
  #
  # Usage in ERB templates:
  #
  #   <%= style_capsule do %>
  #     <style>
  #       .section { color: red; }
  #       .heading:hover { opacity: 0.8; }
  #     </style>
  #     <div class="section">
  #       <h2 class="heading">Hello</h2>
  #     </div>
  #   <% end %>
  #
  # The CSS will be automatically scoped and content wrapped in a scoped div.
  # The <style> tag will be extracted and processed separately.
  module Helper
    # Maximum HTML content size (10MB) to prevent DoS attacks
    MAX_HTML_SIZE = 10_000_000
    # Generate capsule ID based on caller location for uniqueness
    def generate_capsule_id(css_content)
      # Use caller location + CSS content for uniqueness
      caller_info = caller_locations(1, 1).first
      capsule_key = "#{caller_info.path}:#{caller_info.lineno}:#{css_content}"
      "a#{Digest::SHA1.hexdigest(capsule_key)}"[0, 8]
    end

    # Scope CSS content and return scoped CSS
    def scope_css(css_content, capsule_id)
      # Use thread-local cache to avoid reprocessing
      cache_key = "style_capsule_#{capsule_id}"

      if Thread.current[cache_key]
        return Thread.current[cache_key]
      end

      scoped_css = CssProcessor.scope_selectors(css_content, capsule_id)
      Thread.current[cache_key] = scoped_css
      scoped_css
    end

    # ERB helper: automatically wraps content in scoped div and processes CSS
    #
    # Extracts <style> tags from content, processes them, and wraps everything
    # in a scoped div. CSS can be in <style> tags or as a separate block.
    #
    # Usage:
    #   <%= style_capsule do %>
    #     <style>
    #       .section { color: red; }
    #       .heading:hover { opacity: 0.8; }
    #     </style>
    #     <div class="section">
    #       <h2 class="heading">Hello</h2>
    #     </div>
    #   <% end %>
    #
    # Or with CSS as separate content:
    #   <% css_content = capture do %>
    #     .section { color: red; }
    #   <% end %>
    #   <%= style_capsule(css_content) do %>
    #     <div class="section">Content</div>
    #   <% end %>
    #
    # Or with manual capsule ID (for testing/exact naming):
    #   <%= style_capsule(capsule_id: "test-123") do %>
    #     <style>.section { color: red; }</style>
    #     <div class="section">Content</div>
    #   <% end %>
    #
    # Or with both CSS content and manual capsule ID:
    #   <% css_content = ".section { color: red; }" %>
    #   <%= style_capsule(css_content, capsule_id: "test-123") do %>
    #     <div class="section">Content</div>
    #   <% end %>
    def style_capsule(css_content = nil, capsule_id: nil, &content_block)
      html_content = nil

      # If CSS content is provided as argument, use it
      # Otherwise, extract from content block
      if css_content.nil? && block_given?
        full_content = capture(&content_block)

        # Validate HTML content size to prevent DoS attacks
        if full_content.bytesize > MAX_HTML_SIZE
          raise ArgumentError, "HTML content exceeds maximum size of #{MAX_HTML_SIZE} bytes (got #{full_content.bytesize} bytes)"
        end

        # Extract <style> tags from content
        # Note: Pattern uses non-greedy matching (.*?) to minimize backtracking
        # Size limit (MAX_HTML_SIZE) mitigates ReDoS risk from malicious input
        style_match = full_content.match(/<style[^>]*>(.*?)<\/style>/m)
        if style_match
          css_content = style_match[1]
          # Use sub instead of gsub to only remove first occurrence (reduces backtracking)
          html_content = full_content.sub(/<style[^>]*>.*?<\/style>/m, "").strip
        else
          # No style tag found, treat entire content as HTML
          css_content = nil
          html_content = full_content
        end
      elsif css_content && block_given?
        html_content = capture(&content_block)
      elsif css_content && !block_given?
        # CSS provided but no content block - just return scoped CSS
        capsule_id ||= generate_capsule_id(css_content)
        scoped_css = scope_css(css_content, capsule_id)
        return content_tag(:style, raw(scoped_css), type: "text/css").html_safe
      else
        return ""
      end

      # If no CSS, just return content
      return html_content.html_safe if css_content.nil? || css_content.to_s.strip.empty?

      # Use provided capsule_id or generate one
      capsule_id ||= generate_capsule_id(css_content)
      scoped_css = scope_css(css_content, capsule_id)

      # Render style tag and wrapped content
      style_tag = content_tag(:style, raw(scoped_css), type: "text/css")
      wrapped_content = content_tag(:div, raw(html_content), data: {capsule: capsule_id})

      (style_tag + wrapped_content).html_safe
    end

    # Register a stylesheet file for head rendering
    #
    # Usage in ERB:
    #   <% register_stylesheet("stylesheets/user/my_component", "data-turbo-track": "reload") %>
    #   <% register_stylesheet("stylesheets/admin/dashboard", namespace: :admin) %>
    #
    # @param file_path [String] Path to stylesheet (relative to app/assets/stylesheets)
    # @param namespace [Symbol, String, nil] Optional namespace for separation (nil/blank uses default)
    # @param options [Hash] Options for stylesheet_link_tag
    # @return [void]
    def register_stylesheet(file_path, namespace: nil, **options)
      StyleCapsule::StylesheetRegistry.register(file_path, namespace: namespace, **options)
    end

    # Render StyleCapsule registered stylesheets
    #
    # Usage in ERB:
    #   <%= stylesheet_registry_tags %>
    #   <%= stylesheet_registry_tags(namespace: :admin) %>
    #
    # @param namespace [Symbol, String, nil] Optional namespace to render (nil/blank renders all)
    # @return [String] HTML-safe string with stylesheet tags
    def stylesheet_registry_tags(namespace: nil)
      StyleCapsule::StylesheetRegistry.render_head_stylesheets(self, namespace: namespace)
    end

    # @deprecated Use {#stylesheet_registry_tags} instead.
    #   This method name will be removed in a future version.
    alias_method :stylesheet_registrymap_tags, :stylesheet_registry_tags
  end
end
