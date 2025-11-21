# frozen_string_literal: true

module StyleCapsule
  # Builds CSS files from StyleCapsule components
  #
  # This class extracts the logic from the rake task so it can be tested independently.
  # The rake task delegates to this class.
  class ComponentBuilder
    class << self
      # Check if Phlex is available
      # This method can be stubbed in tests to test fallback paths
      def phlex_available?
        !!defined?(Phlex::HTML)
      end

      # Check if ViewComponent is available
      # This method can be stubbed in tests to test fallback paths
      def view_component_available?
        !!defined?(ViewComponent::Base)
      end

      # Find all Phlex components that use StyleCapsule
      #
      # @return [Array<Class>] Array of component classes
      def find_phlex_components
        return [] unless phlex_available?

        components = []
        ObjectSpace.each_object(Class) do |klass|
          if klass < Phlex::HTML && klass.included_modules.include?(StyleCapsule::Component)
            components << klass
          end
        end
        components
      end

      # Find all ViewComponent components that use StyleCapsule
      #
      # @return [Array<Class>] Array of component classes
      def find_view_components
        return [] unless view_component_available?

        components = []
        begin
          ObjectSpace.each_object(Class) do |klass|
            if klass < ViewComponent::Base && klass.included_modules.include?(StyleCapsule::ViewComponent)
              components << klass
            end
          rescue
            # Skip this class if checking inheritance triggers ViewComponent loading errors
            # (e.g., ViewComponent 2.83.0 has a bug with Gem::Version#to_f)
            next
          end
        rescue
          # ViewComponent may have loading issues (e.g., version compatibility)
          # Silently skip ViewComponent components if there's an error
          # This allows the rake task to continue with Phlex components
        end
        components
      end

      # Collect all component classes that use StyleCapsule
      #
      # @return [Array<Class>] Array of component classes
      def collect_components
        find_phlex_components + find_view_components
      end

      # Build CSS file for a single component
      #
      # @param component_class [Class] Component class to build
      # @param output_proc [Proc, nil] Optional proc to call with output messages
      # @return [String, nil] Generated file path or nil if skipped
      def build_component(component_class, output_proc: nil)
        return nil unless component_class.inline_cache_strategy == :file
        # Check for class method component_styles (required for file caching)
        return nil unless component_class.respond_to?(:component_styles, false)

        begin
          # Use class method component_styles for file caching
          css_content = component_class.component_styles
          return nil if css_content.nil? || css_content.to_s.strip.empty?

          # Create a temporary instance to get capsule
          # Some components might require arguments, so we catch errors
          instance = component_class.new
          capsule_id = instance.component_capsule
          scoped_css = instance.send(:scope_css, css_content)

          # Write CSS file
          file_path = CssFileWriter.write_css(
            css_content: scoped_css,
            component_class: component_class,
            capsule_id: capsule_id
          )

          output_proc&.call("Generated: #{file_path}") if file_path
          file_path
        rescue ArgumentError, NoMethodError => e
          # Component requires arguments or has dependencies - skip it
          output_proc&.call("Skipped #{component_class.name}: #{e.message}")
          nil
        end
      end

      # Build CSS files for all components
      #
      # @param output_proc [Proc, nil] Optional proc to call with output messages
      # @return [Integer] Number of files generated
      def build_all(output_proc: nil)
        require "style_capsule/css_file_writer"

        # Ensure output directory exists
        CssFileWriter.ensure_output_directory

        # Collect all component classes that use StyleCapsule
        component_classes = collect_components

        # Generate CSS files for each component
        generated_count = 0
        component_classes.each do |component_class|
          file_path = build_component(component_class, output_proc: output_proc)
          generated_count += 1 if file_path
        end

        output_proc&.call("StyleCapsule CSS files built successfully")
        generated_count
      end
    end
  end
end
