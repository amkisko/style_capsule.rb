# frozen_string_literal: true

module StyleCapsule
  # Railtie to automatically include StyleCapsule helpers in Rails
  if defined?(Rails::Railtie)
    class Railtie < Rails::Railtie
      # Automatically include ERB helper in ActionView::Base (standard Rails pattern)
      # This makes helpers available in all ERB templates automatically
      ActiveSupport.on_load(:action_view) do
        include StyleCapsule::Helper
      end

      # Configure CSS file writer for file-based caching
      config.after_initialize do
        # Configure default output directory
        StyleCapsule::CssFileWriter.configure(
          output_dir: Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR),
          enabled: true
        )

        # Add output directory to asset paths if it exists
        if Rails.application.config.respond_to?(:assets)
          capsules_dir = Rails.root.join(StyleCapsule::CssFileWriter::DEFAULT_OUTPUT_DIR)
          if Dir.exist?(capsules_dir)
            Rails.application.config.assets.paths << capsules_dir
          end
        end
      end

      # Clear CSS caches and stylesheet manifest when classes are unloaded in development
      # This prevents memory leaks from stale cache entries during code reloading
      if Rails.env.development?
        config.to_prepare do
          # Clear CSS caches for all classes that include StyleCapsule modules
          # Skip singleton classes and handle errors gracefully
          ObjectSpace.each_object(Class) do |klass|
            # Skip singleton classes and classes without names (they can cause errors)
            # Singleton classes don't have proper names and can't be safely checked
            # Use fallback for blank? if ActiveSupport not available
            name = klass.name
            next if name.nil? || (name.respond_to?(:blank?) ? name.blank? : name.to_s.strip.empty?)
            next if klass.singleton_class?

            # Use method_defined? instead of respond_to? to avoid triggering delegation
            # that might cause errors with singleton classes or other edge cases
            begin
              if klass.method_defined?(:clear_css_cache, false) || klass.private_method_defined?(:clear_css_cache)
                klass.clear_css_cache
              end
            rescue
              # Skip classes that cause errors (singleton classes, delegation issues, etc.)
              next
            end
          end

          # Clear stylesheet manifest to allow re-registration during code reload
          StyleCapsule::StylesheetRegistry.clear_manifest
        end
      end

      # Load rake tasks for CSS file building
      rake_tasks do
        load File.expand_path("../tasks/style_capsule.rake", __dir__)
      end

      # Note: PhlexHelper should be included explicitly in ApplicationComponent
      # or your base Phlex component class, not automatically via Railtie
    end
  end
end
