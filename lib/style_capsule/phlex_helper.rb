# frozen_string_literal: true

module StyleCapsule
  # Phlex helper module for StyleCapsule stylesheet registry
  #
  # Include this in your base Phlex component class (e.g., ApplicationComponent):
  #   class ApplicationComponent < Phlex::HTML
  #     include StyleCapsule::PhlexHelper
  #   end
  #
  # Usage in Phlex layouts:
  #   head do
  #     stylesheet_registry_tags
  #   end
  #
  # Usage in Phlex components:
  #   class MyComponent < ApplicationComponent
  #     include StyleCapsule::PhlexHelper
  #     styles_namespace :user  # Set default namespace
  #
  #     def view_template
  #       register_stylesheet("stylesheets/user/my_component")  # Uses :user namespace automatically
  #       div { "Content" }
  #     end
  #   end
  module PhlexHelper
    # Register a stylesheet file for head rendering
    #
    # Usage in Phlex components:
    #   def view_template
    #     register_stylesheet("stylesheets/user/my_component", "data-turbo-track": "reload")
    #     register_stylesheet("stylesheets/admin/dashboard", namespace: :admin)
    #     div { "Content" }
    #   end
    #
    # If the component has a default namespace set via styles_namespace or stylesheet_registry,
    # it will be used automatically when namespace is not explicitly provided.
    #
    # @param file_path [String] Path to stylesheet (relative to app/assets/stylesheets)
    # @param namespace [Symbol, String, nil] Optional namespace for separation (nil/blank uses component's default or global default)
    # @param options [Hash] Options for stylesheet_link_tag
    # @return [void]
    def register_stylesheet(file_path, namespace: nil, **options)
      # Use component's default namespace if not explicitly provided
      if namespace.nil? && respond_to?(:class) && self.class.respond_to?(:stylesheet_namespace)
        namespace = self.class.stylesheet_namespace
      end
      StyleCapsule::StylesheetRegistry.register(file_path, namespace: namespace, **options)
    end

    # Render StyleCapsule registered stylesheets
    #
    # Usage in Phlex layouts:
    #   head do
    #     stylesheet_registry_tags
    #     stylesheet_registry_tags(namespace: :admin)
    #   end
    #
    # @param namespace [Symbol, String, nil] Optional namespace to render (nil/blank renders all)
    # @return [void] Renders stylesheet tags via raw
    def stylesheet_registry_tags(namespace: nil)
      output = StyleCapsule::StylesheetRegistry.render_head_stylesheets(view_context, namespace: namespace)
      # Phlex's raw() requires the object to be marked as safe
      # Use Phlex's safe() if available, otherwise fall back to html_safe for test doubles
      # The output from render_head_stylesheets is already html_safe (SafeBuffer)
      output_string = output.to_s

      if respond_to?(:safe)
        # Real Phlex component - use raw() for rendering
        safe_content = safe(output_string)
        raw(safe_content)
      end

      # Always return the output string for testing/compatibility
      output_string
    end
  end
end
