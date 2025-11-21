# frozen_string_literal: true

require "digest/sha1"
require "cgi"

module StyleCapsule
  # Standalone helper module for use without Rails
  #
  # This module provides basic HTML generation and CSS scoping functionality
  # without requiring Rails ActionView helpers. It can be included in any
  # framework's view context or used directly.
  #
  # @example Usage in Sinatra
  #   class MyApp < Sinatra::Base
  #     helpers StyleCapsule::StandaloneHelper
  #   end
  #
  # @example Usage in plain Ruby
  #   class MyView
  #     include StyleCapsule::StandaloneHelper
  #   end
  #
  # @example Usage in ERB (non-Rails)
  #   # In your ERB template context
  #   include StyleCapsule::StandaloneHelper
  #   style_capsule do
  #     "<style>.section { color: red; }</style><div class='section'>Content</div>"
  #   end
  module StandaloneHelper
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

    # Generate HTML tag without Rails helpers
    #
    # @param tag [String, Symbol] HTML tag name
    # @param content [String, nil] Tag content (or use block)
    # @param options [Hash] HTML attributes
    # @param block [Proc] Block for tag content
    # @return [String] HTML string
    def content_tag(tag, content = nil, **options, &block)
      tag_name = tag.to_s
      content = capture(&block) if block_given? && content.nil?
      content ||= ""

      attrs = options.map do |k, v|
        if v.is_a?(Hash)
          # Handle nested attributes like data: { capsule: "abc" }
          v.map { |nk, nv| %(#{k}-#{nk}="#{escape_html_attr(nv)}") }.join(" ")
        else
          %(#{k}="#{escape_html_attr(v)}")
        end
      end.join(" ")

      attrs = " #{attrs}" unless attrs.empty?
      "<#{tag_name}#{attrs}>#{content}</#{tag_name}>"
    end

    # Capture block content (simplified version without Rails)
    #
    # @param block [Proc] Block to capture
    # @return [String] Captured content
    def capture(&block)
      return "" unless block_given?
      block.call.to_s
    end

    # Mark string as HTML-safe (for compatibility)
    #
    # @param string [String] String to mark as safe
    # @return [String] HTML-safe string
    def html_safe(string)
      # In non-Rails context, just return the string
      # If ActiveSupport is available, use its html_safe
      if string.respond_to?(:html_safe)
        string.html_safe
      else
        string
      end
    end

    # Raw string (no HTML escaping)
    #
    # @param string [String] String to return as-is
    # @return [String] Raw string
    def raw(string)
      html_safe(string.to_s)
    end

    # ERB helper: automatically wraps content in scoped div and processes CSS
    #
    # @param css_content [String, nil] CSS content (or extract from block)
    # @param capsule_id [String, nil] Optional capsule ID
    # @param content_block [Proc] Block containing HTML content
    # @return [String] HTML with scoped CSS and wrapped content
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
        style_match = full_content.match(/<style[^>]*>(.*?)<\/style>/m)
        if style_match
          css_content = style_match[1]
          html_content = full_content.sub(/<style[^>]*>.*?<\/style>/m, "").strip
        else
          css_content = nil
          html_content = full_content
        end
      elsif css_content && block_given?
        html_content = capture(&content_block)
      elsif css_content && !block_given?
        # CSS provided but no content block - just return scoped CSS
        capsule_id ||= generate_capsule_id(css_content)
        scoped_css = scope_css(css_content, capsule_id)
        return content_tag(:style, raw(scoped_css), type: "text/css")
      else
        return ""
      end

      # If no CSS, just return content
      return html_safe(html_content) if css_content.nil? || css_content.to_s.strip.empty?

      # Use provided capsule_id or generate one
      capsule_id ||= generate_capsule_id(css_content)
      scoped_css = scope_css(css_content, capsule_id)

      # Render style tag and wrapped content
      style_tag = content_tag(:style, raw(scoped_css), type: "text/css")
      wrapped_content = content_tag(:div, raw(html_content), data: {capsule: capsule_id})

      html_safe(style_tag + wrapped_content)
    end

    # Register a stylesheet file for head rendering
    #
    # @param file_path [String] Path to stylesheet
    # @param namespace [Symbol, String, nil] Optional namespace
    # @param options [Hash] Options for stylesheet link tag
    # @return [void]
    def register_stylesheet(file_path, namespace: nil, **options)
      StyleCapsule::StylesheetRegistry.register(file_path, namespace: namespace, **options)
    end

    # Render StyleCapsule registered stylesheets
    #
    # @param namespace [Symbol, String, nil] Optional namespace to render
    # @return [String] HTML-safe string with stylesheet tags
    def stylesheet_registry_tags(namespace: nil)
      StyleCapsule::StylesheetRegistry.render_head_stylesheets(self, namespace: namespace)
    end

    # @deprecated Use {#stylesheet_registry_tags} instead.
    #   This method name will be removed in a future version.
    alias_method :stylesheet_registrymap_tags, :stylesheet_registry_tags

    private

    # Escape HTML attribute value
    #
    # @param value [String] Value to escape
    # @return [String] Escaped value
    def escape_html_attr(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
