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
  #     helpers.stylesheet_registrymap_tags
  #   end
  #
  # Usage in ViewComponent components:
  #   def call
  #     register_stylesheet("stylesheets/user/my_component")
  #     content_tag(:div, "Content")
  #   end
  module ViewComponentHelper
    # Register a stylesheet file for head injection
    #
    # Usage in ViewComponent components:
    #   def call
    #     register_stylesheet("stylesheets/user/my_component", "data-turbo-track": "reload")
    #     register_stylesheet("stylesheets/admin/dashboard", namespace: :admin)
    #     content_tag(:div, "Content")
    #   end
    #
    # @param file_path [String] Path to stylesheet (relative to app/assets/stylesheets)
    # @param namespace [Symbol, String, nil] Optional namespace for separation (nil/blank uses default)
    # @param options [Hash] Options for stylesheet_link_tag
    # @return [void]
    def register_stylesheet(file_path, namespace: nil, **options)
      StyleCapsule::StylesheetRegistry.register(file_path, namespace: namespace, **options)
    end

    # Render StyleCapsule registered stylesheets (similar to javascript_importmap_tags)
    #
    # Usage in ViewComponent layouts:
    #   def call
    #     helpers.stylesheet_registrymap_tags
    #     helpers.stylesheet_registrymap_tags(namespace: :admin)
    #   end
    #
    # @param namespace [Symbol, String, nil] Optional namespace to render (nil/blank renders all)
    # @return [String] HTML-safe string with stylesheet tags
    def stylesheet_registrymap_tags(namespace: nil)
      StyleCapsule::StylesheetRegistry.render_head_stylesheets(helpers, namespace: namespace)
    end
  end
end
