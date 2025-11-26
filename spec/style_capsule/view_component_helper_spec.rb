# frozen_string_literal: true

RSpec.describe StyleCapsule::ViewComponentHelper do
  let(:view_context_double) do
    instance_double("ActionView::Base",
      stylesheet_link_tag: '<link rel="stylesheet">',
      content_tag: "<style></style>")
  end

  let(:helper_class) do
    Class.new do
      include StyleCapsule::ViewComponentHelper

      attr_accessor :view_context_double

      def helpers
        @view_context_double
      end
    end
  end

  let(:helper) do
    instance = helper_class.new
    instance.view_context_double = view_context_double
    instance
  end

  before do
    StyleCapsule::StylesheetRegistry.clear
    StyleCapsule::StylesheetRegistry.clear_manifest
    StyleCapsule::StylesheetRegistry.clear_inline_cache
  end

  describe "#register_stylesheet" do
    it "registers a stylesheet file" do
      helper.register_stylesheet("stylesheets/my_component")
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end

    it "registers with namespace" do
      helper.register_stylesheet("stylesheets/admin/dashboard", namespace: :admin)
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :admin)).to be true
    end

    it "registers with options" do
      helper.register_stylesheet("stylesheets/my_component", "data-turbo-track": "reload")
      stylesheets = StyleCapsule::StylesheetRegistry.stylesheets_for
      expect(stylesheets.first[:options][:"data-turbo-track"]).to eq("reload")
    end

    it "uses component's default namespace when namespace is not provided" do
      component_class = Class.new(ViewComponent::Base) do
        include StyleCapsule::ViewComponent
        include StyleCapsule::ViewComponentHelper

        style_capsule namespace: :user

        attr_accessor :view_context_double

        def initialize(view_context: nil)
          @view_context_double = view_context
        end

        def helpers
          @view_context_double
        end
      end
      # Give component class a name for ViewComponent 4.x compatibility
      Object.const_set("TestComponent_#{component_class.object_id}", component_class) unless component_class.name

      component = component_class.new(view_context: view_context_double)

      component.register_stylesheet("stylesheets/user/my_component")
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :user)).to be true
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :default)).to be false
    end

    it "uses explicit namespace over component's default namespace" do
      component_class = Class.new(ViewComponent::Base) do
        include StyleCapsule::ViewComponent
        include StyleCapsule::ViewComponentHelper

        style_capsule namespace: :user

        attr_accessor :view_context_double

        def initialize(view_context: nil)
          @view_context_double = view_context
        end

        def helpers
          @view_context_double
        end
      end
      # Give component class a name for ViewComponent 4.x compatibility
      Object.const_set("TestComponentOverride_#{component_class.object_id}", component_class) unless component_class.name

      component = component_class.new(view_context: view_context_double)

      component.register_stylesheet("stylesheets/admin/dashboard", namespace: :admin)
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :admin)).to be true
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :user)).to be false
    end

    it "does not use default namespace when component doesn't have stylesheet_namespace method" do
      helper_class_without_namespace = Class.new do
        include StyleCapsule::ViewComponentHelper

        attr_accessor :view_context_double

        def helpers
          @view_context_double
        end
      end

      helper_without_namespace = helper_class_without_namespace.new
      helper_without_namespace.view_context_double = view_context_double

      helper_without_namespace.register_stylesheet("stylesheets/my_component")
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end
  end

  describe "#stylesheet_registrymap_tags" do
    it "calls render_head_stylesheets with helpers" do
      helper.register_stylesheet("stylesheets/my_component")
      view_context = helper.helpers
      expect(StyleCapsule::StylesheetRegistry).to receive(:render_head_stylesheets)
        .with(view_context, namespace: nil)
        .and_return('<link rel="stylesheet">')
      helper.stylesheet_registrymap_tags
    end

    it "renders registered stylesheets and clears registry" do
      helper.register_stylesheet("stylesheets/my_component")
      helper.stylesheet_registrymap_tags
      # File registrations persist in manifest (process-wide), so any? returns true
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
      # But inline CSS should be cleared (request-scoped)
      expect(StyleCapsule::StylesheetRegistry.request_inline_stylesheets).to be_empty
    end

    it "renders specific namespace" do
      helper.register_stylesheet("stylesheets/admin", namespace: :admin)
      helper.register_stylesheet("stylesheets/user", namespace: :user)
      helper.stylesheet_registrymap_tags(namespace: :admin)
      # File registrations persist in manifest (process-wide)
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :user)).to be true # User namespace should remain
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :admin)).to be true # Admin should remain (manifest persists)
    end

    it "passes namespace to render_head_stylesheets" do
      helper.register_stylesheet("stylesheets/admin", namespace: :admin)
      view_context = helper.helpers
      expect(StyleCapsule::StylesheetRegistry).to receive(:render_head_stylesheets)
        .with(view_context, namespace: :admin)
        .and_return('<link rel="stylesheet">')
      helper.stylesheet_registrymap_tags(namespace: :admin)
    end
  end
end
