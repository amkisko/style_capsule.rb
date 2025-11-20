# frozen_string_literal: true

namespace :style_capsule do
  desc "Build StyleCapsule CSS files from components (similar to Tailwind CSS build)"
  task build: :environment do
    require "style_capsule/css_file_writer"

    # Ensure output directory exists
    StyleCapsule::CssFileWriter.ensure_output_directory

    # Collect all component classes that use StyleCapsule
    component_classes = []

    # Find Phlex components
    if defined?(Phlex::HTML)
      ObjectSpace.each_object(Class) do |klass|
        if klass < Phlex::HTML && klass.included_modules.include?(StyleCapsule::Component)
          component_classes << klass
        end
      end
    end

    # Find ViewComponent components
    # Wrap in begin/rescue to handle ViewComponent loading errors (e.g., version compatibility issues)
    begin
      if defined?(ViewComponent::Base)
        ObjectSpace.each_object(Class) do |klass|
          if klass < ViewComponent::Base && klass.included_modules.include?(StyleCapsule::ViewComponent)
            component_classes << klass
          end
        rescue
          # Skip this class if checking inheritance triggers ViewComponent loading errors
          # (e.g., ViewComponent 2.83.0 has a bug with Gem::Version#to_f)
          next
        end
      end
    rescue
      # ViewComponent may have loading issues (e.g., version compatibility)
      # Silently skip ViewComponent components if there's an error
      # This allows the rake task to continue with Phlex components
    end

    # Generate CSS files for each component
    component_classes.each do |component_class|
      next unless component_class.inline_cache_strategy == :file
      # Check for class method component_styles (required for file caching)
      next unless component_class.respond_to?(:component_styles, false)

      begin
        # Use class method component_styles for file caching
        css_content = component_class.component_styles
        next if css_content.nil? || css_content.to_s.strip.empty?

        # Create a temporary instance to get capsule
        # Some components might require arguments, so we catch errors
        instance = component_class.new
        capsule_id = instance.component_capsule
        scoped_css = instance.send(:scope_css, css_content)

        # Write CSS file
        file_path = StyleCapsule::CssFileWriter.write_css(
          css_content: scoped_css,
          component_class: component_class,
          capsule_id: capsule_id
        )

        puts "Generated: #{file_path}" if file_path
      rescue ArgumentError, NoMethodError => e
        # Component requires arguments or has dependencies - skip it
        puts "Skipped #{component_class.name}: #{e.message}"
        next
      end
    end

    puts "StyleCapsule CSS files built successfully"
  end

  desc "Clear StyleCapsule generated CSS files"
  task clear: :environment do
    require "style_capsule/css_file_writer"
    StyleCapsule::CssFileWriter.clear_files
    puts "StyleCapsule CSS files cleared"
  end
end

# Hook into Rails asset precompilation (similar to Tailwind CSS)
if defined?(Rails)
  Rake::Task["assets:precompile"].enhance(["style_capsule:build"]) if Rake::Task.task_defined?("assets:precompile")
end
