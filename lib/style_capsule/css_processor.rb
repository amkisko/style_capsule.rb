# frozen_string_literal: true

require_relative "instrumentation"

module StyleCapsule
  # Shared CSS processing logic for scoping selectors with attribute selectors
  #
  # Supports two scoping strategies:
  # 1. Selector patching (default): Adds [data-capsule="..."] prefix to each selector
  #    - Wider browser support (all modern browsers)
  #    - Requires CSS parsing and transformation
  # 2. CSS nesting (optional): Wraps style rules in [data-capsule="..."] { ... }
  #    - Avoids per-selector rewrite
  #    - Requires CSS nesting support (Chrome 112+, Firefox 117+, Safari 16.5+)
  #    - Hoists non-nestable at-rules (@keyframes, @font-face, @import, ...) to top level
  # rubocop:disable Metrics/ModuleLength -- processor owns patching, nesting hoist, and validation
  module CssProcessor
    # Maximum CSS content size (1MB) to prevent DoS attacks
    MAX_CSS_SIZE = 1_000_000

    # At-rules whose inner selectors must not receive attribute scoping
    NON_SCOPING_AT_RULES = %w[keyframes font-face property].freeze

    # At-rules that must stay at the top level under CSS nesting
    HOISTABLE_AT_RULES = %w[
      keyframes font-face import charset namespace property
    ].freeze

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
    # Uses attribute selectors instead of renaming classes, so styles apply only
    # within scoped components. Leaves @keyframes / @font-face / @property steps alone.
    #
    # @param css_string [String] Original CSS content
    # @param capsule_id [String] The capsule ID to use in attribute selector
    # @param component_class [Class, String, nil] Optional component class for instrumentation
    # @return [String] CSS with scoped selectors
    # @raise [ArgumentError] If CSS content exceeds maximum size or capsule_id is invalid
    def self.scope_selectors(css_string, capsule_id, component_class: nil)
      return css_string if css_string.nil? || css_string.strip.empty?

      if css_string.bytesize > MAX_CSS_SIZE
        raise ArgumentError, "CSS content exceeds maximum size of #{MAX_CSS_SIZE} bytes (got #{css_string.bytesize} bytes)"
      end

      reject_style_element_breakout!(css_string)
      validate_capsule_id!(capsule_id)

      Instrumentation.instrument_css_processing(
        strategy: :selector_patching,
        component_class: component_class || "Unknown",
        capsule_id: capsule_id,
        css_content: css_string
      ) do
        capsule_attr = %([data-capsule="#{capsule_id}"])
        patch_selectors(strip_comments(css_string.dup), capsule_attr)
      end
    end

    # Scope CSS using CSS nesting (wraps nestable rules in [data-capsule] { ... })
    #
    # Avoids per-selector rewrite. Requires CSS nesting support in browsers
    # (Chrome 112+, Firefox 117+, Safari 16.5+). Non-nestable at-rules are written
    # before the wrapper so @keyframes and @font-face stay valid.
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
    # @return [String] CSS with nesting wrapper and hoisted at-rules
    # @raise [ArgumentError] If CSS content exceeds maximum size or capsule_id is invalid
    # rubocop:disable Metrics/AbcSize -- size check, breakout, instrument, then hoist and wrap
    def self.scope_with_nesting(css_string, capsule_id, component_class: nil)
      return css_string if css_string.nil? || css_string.strip.empty?

      if css_string.bytesize > MAX_CSS_SIZE
        raise ArgumentError, "CSS content exceeds maximum size of #{MAX_CSS_SIZE} bytes (got #{css_string.bytesize} bytes)"
      end

      reject_style_element_breakout!(css_string)
      validate_capsule_id!(capsule_id)

      Instrumentation.instrument_css_processing(
        strategy: :nesting,
        component_class: component_class || "Unknown",
        capsule_id: capsule_id,
        css_content: css_string
      ) do
        capsule_attr = %([data-capsule="#{capsule_id}"])
        hoisted, nestable = hoist_top_level_at_rules(css_string)
        parts = []
        parts << hoisted unless hoisted.empty?
        parts << "#{capsule_attr} {\n#{nestable}\n}" unless nestable.strip.empty?
        parts.join("\n")
      end
    end
    # rubocop:enable Metrics/AbcSize

    # Strip CSS comments (/* ... */) from the string
    #
    # @param css [String] CSS content with comments
    # @return [String] CSS content without comments
    def self.strip_comments(css)
      css.gsub(/\/\*.*?\*\//m, "")
    end

    # Reject CSS that would close an enclosing HTML style element
    #
    # HTML parses style-element content until the first case-insensitive closer,
    # including sequences inside CSS comments or string literals.
    #
    # @param css_string [String, nil] CSS that will be placed inside a style tag
    # @raise [ArgumentError] If the string contains a style element closer
    def self.reject_style_element_breakout!(css_string)
      # Core path must not call ActiveSupport String#blank?
      # rubocop:disable Rails/Blank -- standalone hosts may lack ActiveSupport
      return if css_string.nil? || css_string.empty?
      # rubocop:enable Rails/Blank
      return unless css_string.match?(%r{</style}i)

      raise ArgumentError, "CSS content must not contain a style element closer"
    end

    # Validate capsule ID to prevent injection attacks
    #
    # @param capsule_id [String] Capsule ID to validate
    # @raise [ArgumentError] If capsule_id is invalid
    def self.validate_capsule_id!(capsule_id)
      unless capsule_id.is_a?(String)
        raise ArgumentError, "capsule_id must be a String (got #{capsule_id.class})"
      end

      if capsule_id.empty?
        raise ArgumentError, "capsule_id cannot be empty"
      end

      unless capsule_id.match?(/\A[a-zA-Z0-9_-]+\z/)
        raise ArgumentError, "Invalid capsule_id: must contain only alphanumeric characters, hyphens, and underscores (got: #{capsule_id.inspect})"
      end

      if capsule_id.length > 100
        raise ArgumentError, "Invalid capsule_id: too long (max 100 characters, got #{capsule_id.length})"
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- walks braces and at-rules in one pass
    def self.patch_selectors(css, capsule_attr)
      output = +""
      index = 0
      length = css.length
      brace_depth = 0
      suppress_below_depth = nil

      while index < length
        while index < length && css[index].match?(/\s/)
          output << css[index]
          index += 1
        end
        break if index >= length

        if css[index] == "}"
          output << "}"
          index += 1
          brace_depth -= 1
          if !suppress_below_depth.nil? && brace_depth <= suppress_below_depth
            suppress_below_depth = nil
          end
          next
        end

        selector_start = index
        while index < length && css[index] != "{" && css[index] != "}"
          index += 1
        end

        selectors_raw = css[selector_start...index]
        if index >= length || css[index] == "}"
          output << selectors_raw
          next
        end

        selectors = selectors_raw.strip
        at_name = selectors[/\A@([a-zA-Z-]+)/, 1]&.downcase
        entering_non_scoping = at_name && NON_SCOPING_AT_RULES.include?(at_name) && suppress_below_depth.nil?

        skip_scoping = !suppress_below_depth.nil? ||
          selectors.start_with?("@") ||
          selectors_raw.include?("[data-capsule=") ||
          selectors.empty?

        if skip_scoping
          output << selectors_raw
          if entering_non_scoping
            suppress_below_depth = brace_depth
          end
        else
          scoped_selectors = selectors.split(",").map do |selector|
            selector = selector.strip
            next selector if selector.empty?

            if selector.start_with?(":host")
              selector
                .gsub(/^:host-context\(([^)]+)\)/, "#{capsule_attr} \\1")
                .gsub(/^:host\(([^)]+)\)/, "#{capsule_attr}\\1")
                .gsub(/^:host\b/, capsule_attr)
            else
              "#{capsule_attr} #{selector}"
            end
          end.join(", ")

          leading = selectors_raw[/\A\s*/]
          trailing = selectors_raw[/\s*\z/]
          output << "#{leading}#{scoped_selectors}#{trailing}"
        end

        output << "{"
        index += 1
        brace_depth += 1
      end

      output
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity -- splits top-level CSS into hoistable and nestable parts
    def self.hoist_top_level_at_rules(css)
      hoisted = []
      nestable = +""
      index = 0
      length = css.length

      while index < length
        while index < length && css[index].match?(/\s/)
          nestable << css[index]
          index += 1
        end
        break if index >= length

        if css[index] == "@"
          at_name = css[index..][/\A@([a-zA-Z-]+)/, 1]&.downcase
          if at_name && HOISTABLE_AT_RULES.include?(at_name)
            block, index = read_top_level_at_rule(css, index)
            hoisted << block.strip
            next
          end
        end

        rule, index = read_top_level_rule(css, index)
        nestable << rule
      end

      [hoisted.join("\n"), nestable]
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- semicolon vs braced at-rule forms
    def self.read_top_level_at_rule(css, index)
      start_index = index
      length = css.length

      while index < length && css[index] != "{" && css[index] != ";"
        index += 1
      end

      if index < length && css[index] == ";"
        index += 1
        return [css[start_index...index], index]
      end

      raise ArgumentError, "Unterminated at-rule in CSS" if index >= length

      index = consume_braced_block(css, index)
      [css[start_index...index], index]
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def self.read_top_level_rule(css, index)
      start_index = index
      length = css.length

      while index < length && css[index] != "{"
        index += 1
      end

      return [css[start_index...index], index] if index >= length

      index = consume_braced_block(css, index)
      [css[start_index...index], index]
    end

    # rubocop:disable Metrics/MethodLength -- brace depth walk with unterminated guard
    def self.consume_braced_block(css, index)
      length = css.length
      raise ArgumentError, "Expected opening brace in CSS" unless css[index] == "{"

      depth = 0
      while index < length
        case css[index]
        when "{"
          depth += 1
        when "}"
          depth -= 1
          index += 1
          return index if depth.zero?

          next
        else
          # Non-brace characters stay inside the current block.
        end
        index += 1
      end

      raise ArgumentError, "Unterminated CSS block"
    end
    # rubocop:enable Metrics/MethodLength

    private_class_method :strip_comments, :validate_capsule_id!, :patch_selectors,
      :hoist_top_level_at_rules, :read_top_level_at_rule, :read_top_level_rule,
      :consume_braced_block
  end
  # rubocop:enable Metrics/ModuleLength
end
