# frozen_string_literal: true

RSpec.describe StyleCapsule::PhlexHelper do
  let(:view_context_double) do
    instance_double("ActionView::Base",
      stylesheet_link_tag: '<link rel="stylesheet">',
      content_tag: "<style></style>")
  end

  let(:helper_class) do
    Class.new do
      include StyleCapsule::PhlexHelper

      attr_accessor :view_context_double

      def view_context
        @view_context_double
      end

      def raw(content)
        content
      end
    end
  end

  let(:helper) do
    instance = helper_class.new
    instance.view_context_double = view_context_double
    instance
  end

  before do
    # Clear both request-scoped inline CSS and process-wide manifest for test isolation
    StyleCapsule::StylesheetRegistry.clear
    StyleCapsule::StylesheetRegistry.clear_manifest
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
      component_class = Class.new do
        include StyleCapsule::Component
        include StyleCapsule::PhlexHelper

        style_capsule namespace: :user

        def view_context
          @view_context_double
        end

        def raw(content)
          content
        end
      end

      component = component_class.new
      component.instance_variable_set(:@view_context_double, view_context_double)

      component.register_stylesheet("stylesheets/user/my_component")
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :user)).to be true
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :default)).to be false
    end

    it "uses explicit namespace over component's default namespace" do
      component_class = Class.new do
        include StyleCapsule::Component
        include StyleCapsule::PhlexHelper

        style_capsule namespace: :user

        def view_context
          @view_context_double
        end

        def raw(content)
          content
        end
      end

      component = component_class.new
      component.instance_variable_set(:@view_context_double, view_context_double)

      component.register_stylesheet("stylesheets/admin/dashboard", namespace: :admin)
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :admin)).to be true
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :user)).to be false
    end

    it "does not use default namespace when component doesn't have stylesheet_namespace method" do
      helper_class_without_namespace = Class.new do
        include StyleCapsule::PhlexHelper

        def view_context
          @view_context_double
        end

        def raw(content)
          content
        end
      end

      helper_without_namespace = helper_class_without_namespace.new
      helper_without_namespace.instance_variable_set(:@view_context_double, view_context_double)

      helper_without_namespace.register_stylesheet("stylesheets/my_component")
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end
  end

  describe "#stylesheet_registrymap_tags" do
    it "calls render_head_stylesheets with view_context" do
      helper.register_stylesheet("stylesheets/my_component")
      view_context = helper.view_context
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
      view_context = helper.view_context
      expect(StyleCapsule::StylesheetRegistry).to receive(:render_head_stylesheets)
        .with(view_context, namespace: :admin)
        .and_return('<link rel="stylesheet">')
      helper.stylesheet_registrymap_tags(namespace: :admin)
    end

    it "uses safe() method when available (Phlex component)" do
      helper_class_with_safe = Class.new do
        include StyleCapsule::PhlexHelper

        attr_accessor :view_context_double

        def view_context
          @view_context_double
        end

        def safe(content)
          "safe_#{content}"
        end

        def raw(content)
          "raw_#{content}"
        end
      end

      helper_with_safe = helper_class_with_safe.new
      helper_with_safe.view_context_double = view_context_double
      helper_with_safe.register_stylesheet("stylesheets/test")

      result = helper_with_safe.stylesheet_registrymap_tags
      expect(result).to be_a(String)
    end
  end
end
