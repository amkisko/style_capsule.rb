# frozen_string_literal: true

require_relative "instrumentation"

module StyleCapsule
  # Shared CSS processing logic for scoping selectors with attribute selectors
  #
  # Supports two scoping strategies:
  # 1. Selector patching (default): Adds [data-capsule="..."] prefix to each selector
  #    - Better browser support (all modern browsers)
  #    - Requires CSS parsing and transformation
  # 2. CSS nesting (optional): Wraps entire CSS in [data-capsule="..."] { ... }
  #    - More performant (no parsing needed)
  #    - Requires CSS nesting support (Chrome 112+, Firefox 117+, Safari 16.5+)
  module CssProcessor
    # Maximum CSS content size (1MB) to prevent DoS attacks
    MAX_CSS_SIZE = 1_000_000

    # Rewrite CSS selectors to include attribute-based scoping
    #
    # Transforms:
    #   .section { color: red; }
    #   .heading:hover { opacity: 0.8; }
    #
    # Into:
    #   [data-capsule="a1b2c3d4"] .section { color: red; }
    #   [data-capsule="a1b2c3d4"] .heading:hover { opacity: 0.8; }
    #
    # This approach uses attribute selectors (similar to Angular's Emulated View Encapsulation)
    # instead of renaming classes, ensuring styles only apply within scoped components.
    #
    # Simple approach:
    # - Strips CSS comments first to avoid interference
    # - Finds selectors before opening braces and prefixes them
    # - Handles @media queries (preserves them, scopes inner selectors)
    # - Handles :host and :host-context (component-scoped selectors)
    #
    # @param css_string [String] Original CSS content
    # @param capsule_id [String] The capsule ID to use in attribute selector
    # @param component_class [Class, String, nil] Optional component class for instrumentation
    # @return [String] CSS with scoped selectors
    # @raise [ArgumentError] If CSS content exceeds maximum size or capsule_id is invalid
    def self.scope_selectors(css_string, capsule_id, component_class: nil)
      return css_string if css_string.nil? || css_string.strip.empty?

      # Validate CSS size to prevent DoS attacks
      if css_string.bytesize > MAX_CSS_SIZE
        raise ArgumentError, "CSS content exceeds maximum size of #{MAX_CSS_SIZE} bytes (got #{css_string.bytesize} bytes)"
      end

      # Validate capsule_id
      validate_capsule_id!(capsule_id)

      # Instrument CSS processing with timing and size metrics
      Instrumentation.instrument_css_processing(
        strategy: :selector_patching,
        component_class: component_class || "Unknown",
        capsule_id: capsule_id,
        css_content: css_string
      ) do
        css = css_string.dup
        capsule_attr = %([data-capsule="#{capsule_id}"])

        # Strip CSS comments to avoid interference with selector matching
        # Simple approach: remove /* ... */ comments (including multi-line)
        css_without_comments = strip_comments(css)

        # Process CSS rule by rule
        # Match: selector(s) { ... }
        # Pattern: (start or closing brace) + (whitespace) + (selector text) + (opening brace)
        # Note: Uses non-greedy quantifier ([^{}@]+?) to minimize backtracking
        # MAX_CSS_SIZE limit (1MB) mitigates ReDoS risk from malicious input
        css_without_comments.gsub!(/(^|\})(\s*)([^{}@]+?)(\{)/m) do |_|
          prefix = Regexp.last_match(1)  # Previous closing brace or start
          whitespace = Regexp.last_match(2)  # Whitespace between rules
          selectors_raw = Regexp.last_match(3)  # The selector group
          selectors = selectors_raw.strip  # Stripped for processing
          opening_brace = Regexp.last_match(4)  # The opening brace

          # Skip at-rules (@media, @keyframes, etc.) - they should not be scoped at top level
          next "#{prefix}#{whitespace}#{selectors_raw}#{opening_brace}" if selectors.start_with?("@")

          # Skip if already scoped (avoid double-scoping)
          next "#{prefix}#{whitespace}#{selectors_raw}#{opening_brace}" if selectors_raw.include?("[data-capsule=")

          # Skip empty selectors
          next "#{prefix}#{whitespace}#{selectors_raw}#{opening_brace}" if selectors.empty?

          # Split selectors by comma and scope each one
          scoped_selectors = selectors.split(",").map do |selector|
            selector = selector.strip
            next selector if selector.empty?

            # Handle special component-scoped selectors (:host, :host-context)
            if selector.start_with?(":host")
              selector = selector
                .gsub(/^:host-context\(([^)]+)\)/, "#{capsule_attr} \\1")
                .gsub(/^:host\(([^)]+)\)/, "#{capsule_attr}\\1")
                .gsub(/^:host\b/, capsule_attr)
              selector
            else
              # Add capsule attribute with space before selector for descendant matching
              # This ensures styles apply to elements inside the scoped wrapper
              "#{capsule_attr} #{selector}"
            end
          end.compact.join(", ")

          "#{prefix}#{whitespace}#{scoped_selectors}#{opening_brace}"
        end

        # Restore comments in their original positions
        # Since we stripped comments, we need to put them back
        # For simplicity, we'll just return the processed CSS without comments
        # (comments are typically removed in production CSS anyway)
        css_without_comments
      end
    end

    # Scope CSS using CSS nesting (wraps entire CSS in [data-capsule] { ... })
    #
    # This approach is more performant as it requires no CSS parsing or transformation.
    # However, it requires CSS nesting support in browsers (Chrome 112+, Firefox 117+, Safari 16.5+).
    #
    # Transforms:
    #   .section { color: red; }
    #   .heading:hover { opacity: 0.8; }
    #
    # Into:
    #   [data-capsule="a1b2c3d4"] {
    #     .section { color: red; }
    #     .heading:hover { opacity: 0.8; }
    #   }
    #
    # @param css_string [String] Original CSS content
    # @param capsule_id [String] The capsule ID to use in attribute selector
    # @param component_class [Class, String, nil] Optional component class for instrumentation
    # @return [String] CSS wrapped in nesting selector
    # @raise [ArgumentError] If CSS content exceeds maximum size or capsule_id is invalid
    def self.scope_with_nesting(css_string, capsule_id, component_class: nil)
      return css_string if css_string.nil? || css_string.strip.empty?

      # Validate CSS size to prevent DoS attacks
      if css_string.bytesize > MAX_CSS_SIZE
        raise ArgumentError, "CSS content exceeds maximum size of #{MAX_CSS_SIZE} bytes (got #{css_string.bytesize} bytes)"
      end

      # Validate capsule_id
      validate_capsule_id!(capsule_id)

      # Instrument CSS processing with timing and size metrics
      Instrumentation.instrument_css_processing(
        strategy: :nesting,
        component_class: component_class || "Unknown",
        capsule_id: capsule_id,
        css_content: css_string
      ) do
        # Simply wrap the entire CSS in the capsule attribute selector
        # No parsing or transformation needed - much more performant
        capsule_attr = %([data-capsule="#{capsule_id}"])
        "#{capsule_attr} {\n#{css_string}\n}"
      end
    end

    # Strip CSS comments (/* ... */) from the string
    #
    # @param css [String] CSS content with comments
    # @return [String] CSS content without comments
    def self.strip_comments(css)
      # Remove /* ... */ comments (including multi-line)
      # Use non-greedy match to handle multiple comments
      css.gsub(/\/\*.*?\*\//m, "")
    end

    # Validate capsule ID to prevent injection attacks
    #
    # @param capsule_id [String] Capsule ID to validate
    # @raise [ArgumentError] If capsule_id is invalid
    def self.validate_capsule_id!(capsule_id)
      unless capsule_id.is_a?(String)
        raise ArgumentError, "capsule_id must be a String (got #{capsule_id.class})"
      end

      # Must not be empty (check first for clearer error message)
      if capsule_id.empty?
        raise ArgumentError, "capsule_id cannot be empty"
      end

      # Capsule ID should only contain alphanumeric characters, hyphens, and underscores
      # This prevents injection into HTML attributes
      unless capsule_id.match?(/\A[a-zA-Z0-9_-]+\z/)
        raise ArgumentError, "Invalid capsule_id: must contain only alphanumeric characters, hyphens, and underscores (got: #{capsule_id.inspect})"
      end

      # Reasonable length limit
      if capsule_id.length > 100
        raise ArgumentError, "Invalid capsule_id: too long (max 100 characters, got #{capsule_id.length})"
      end
    end

    private_class_method :strip_comments, :validate_capsule_id!
  end
end
