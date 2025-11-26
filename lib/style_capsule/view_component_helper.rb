# frozen_string_literal: true

module StyleCapsule
  # ViewComponent helper module for StyleCapsule stylesheet registry
  #
  # Include this in your base ViewComponent class (e.g., ApplicationComponent):
  #   class ApplicationComponent < ViewComponent::Base
  #     include StyleCapsule::ViewComponentHelper
  #   end
  #
  # Usage in ViewComponent layouts:
  #   def call
  #     helpers.stylesheet_registry_tags
  #   end
  #
  # Usage in ViewComponent components:
  #   class MyComponent < ApplicationComponent
  #     styles_namespace :user  # Set default namespace
  #
  #     def call
  #       register_stylesheet("stylesheets/user/my_component")  # Uses :user namespace automatically
  #       content_tag(:div, "Content")
  #     end
  #   end
  module ViewComponentHelper
    # Register a stylesheet file for head rendering
    #
    # Usage in ViewComponent components:
    #   def call
    #     register_stylesheet("stylesheets/user/my_component", "data-turbo-track": "reload")
    #     register_stylesheet("stylesheets/admin/dashboard", namespace: :admin)
    #     content_tag(:div, "Content")
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
    # Usage in ViewComponent layouts:
    #   def call
    #     helpers.stylesheet_registry_tags
    #     helpers.stylesheet_registry_tags(namespace: :admin)
    #   end
    #
    # @param namespace [Symbol, String, nil] Optional namespace to render (nil/blank renders all)
    # @return [String] HTML-safe string with stylesheet tags
    def stylesheet_registry_tags(namespace: nil)
      StyleCapsule::StylesheetRegistry.render_head_stylesheets(helpers, namespace: namespace)
    end
  end
end
