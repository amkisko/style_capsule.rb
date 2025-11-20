# frozen_string_literal: true

module StyleCapsule
  # Shared module for component styles support (used by both Component and ViewComponent)
  #
  # Provides unified support for both instance and class method component_styles:
  # - Instance method: `def component_styles` - dynamic rendering, supports all cache strategies except :file
  # - Class method: `def self.component_styles` - static rendering, supports all cache strategies including :file
  module ComponentStylesSupport
    # Check if component defines styles (instance or class method)
    #
    # @return [Boolean]
    def component_styles?
      instance_styles? || class_styles?
    end

    # Resolve component styles (from instance or class method)
    #
    # @return [String, nil] CSS content or nil if no styles defined
    def component_styles_content
      # Prefer instance method for dynamic rendering
      if instance_styles?
        component_styles
      elsif class_styles?
        self.class.component_styles
      end
    end

    # Check if component uses class method styles exclusively (required for file caching)
    #
    # Returns true only if class styles are defined and instance styles are not.
    #
    # @return [Boolean]
    def class_styles_only?
      class_styles? && !instance_styles?
    end

    # Check if file caching is allowed for this component
    #
    # File caching is only allowed for class method component_styles
    #
    # @return [Boolean]
    def file_caching_allowed?
      cache_strategy = self.class.inline_cache_strategy
      return false unless cache_strategy == :file
      class_styles_only?
    end

    private

    # Check if component defines instance method styles
    #
    # @return [Boolean]
    def instance_styles?
      return false unless respond_to?(:component_styles, true)
      styles = component_styles
      styles && !styles.to_s.strip.empty?
    end

    # Check if component defines class method styles
    #
    # @return [Boolean]
    def class_styles?
      return false unless self.class.respond_to?(:component_styles, false)
      begin
        styles = self.class.component_styles
        styles && !styles.to_s.strip.empty?
      rescue NoMethodError
        false
      end
    end
  end
end
