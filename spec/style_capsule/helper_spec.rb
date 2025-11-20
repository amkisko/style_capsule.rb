# frozen_string_literal: true

RSpec.describe StyleCapsule::Helper do
  let(:helper_class) do
    Class.new do
      include StyleCapsule::Helper

      def capture(*args, &block)
        block.call if block_given?
      end

      def content_tag(name, content = nil, options = nil, &block)
        tag_options = if options.is_a?(Hash)
          options.map { |k, v| %(#{k}="#{v}") }.join(" ")
        elsif options
          options.to_s
        else
          ""
        end
        content_str = content || (block_given? ? block.call : "")
        "<#{name}#{" #{tag_options}" unless tag_options.empty?}>#{content_str}</#{name}>"
      end

      def raw(content)
        content
      end
    end
  end

  let(:helper) { helper_class.new }

  describe "#generate_capsule_id" do
    it "generates a scope ID based on caller location" do
      id = helper.generate_capsule_id(".section { color: red; }")
      expect(id).to be_a(String)
      expect(id.length).to eq(8)
      expect(id).to start_with("a")
    end

    it "generates valid IDs with correct format" do
      # Test that IDs are generated correctly
      # Note: IDs include caller location, so same content from different
      # lines will produce different IDs (which is the intended behavior)
      css_content = ".section { color: red; }"
      id1 = helper.generate_capsule_id(css_content)
      id2 = helper.generate_capsule_id(css_content)
      # Both should be valid IDs
      expect(id1).to be_a(String)
      expect(id2).to be_a(String)
      expect(id1.length).to eq(8)
      expect(id2.length).to eq(8)
      expect(id1).to start_with("a")
      expect(id2).to start_with("a")
    end

    it "generates different IDs for different CSS content" do
      id1 = helper.generate_capsule_id(".section { color: red; }")
      id2 = helper.generate_capsule_id(".other { color: blue; }")
      expect(id1).not_to eq(id2)
    end

    it "generates different IDs for different caller locations" do
      id1 = helper.generate_capsule_id(".section { color: red; }")
      # Simulate different caller location by calling from different context
      helper_class.class_eval do
        def generate_capsule_id_different_location(css_content)
          generate_capsule_id(css_content)
        end
      end
      id2 = helper.generate_capsule_id_different_location(".section { color: red; }")
      # Should be different because caller location is different
      expect(id1).not_to eq(id2)
    end
  end

  describe "#scope_css" do
    it "scopes CSS content" do
      css = ".section { color: red; }"
      capsule_id = "abc123"
      result = helper.scope_css(css, capsule_id)
      expect(result).to include('[data-capsule="abc123"]')
      expect(result).to include(".section")
    end

    it "caches scoped CSS" do
      css = ".section { color: red; }"
      capsule_id = "abc123"
      result1 = helper.scope_css(css, capsule_id)
      result2 = helper.scope_css(css, capsule_id)
      expect(result1).to eq(result2)
    end
  end

  describe "#style_capsule" do
    context "with block containing style tag" do
      it "extracts and scopes CSS, wraps content" do
        result = helper.style_capsule do
          <<~HTML
            <style>
              .section { color: red; }
            </style>
            <div class="section">Content</div>
          HTML
        end

        expect(result).to include("<style")
        expect(result).to include("[data-capsule=")
        expect(result).to include('class="section"')
        expect(result).to include("Content")
      end
    end

    context "with CSS content as argument" do
      it "scopes CSS and wraps content" do
        css = ".section { color: red; }"
        result = helper.style_capsule(css) do
          '<div class="section">Content</div>'
        end

        expect(result).to include("<style")
        expect(result).to include("[data-capsule=")
        expect(result).to include("Content")
      end
    end

    context "with manual scope_id" do
      it "uses provided scope_id" do
        result = helper.style_capsule(capsule_id: "test-123") do
          <<~HTML
            <style>.section { color: red; }</style>
            <div class="section">Content</div>
          HTML
        end

        expect(result).to include('data-capsule="test-123"')
      end
    end

    context "with CSS only (no block)" do
      it "returns scoped style tag" do
        css = ".section { color: red; }"
        result = helper.style_capsule(css)
        expect(result).to include("<style")
        expect(result).to include("[data-capsule=")
      end
    end

    context "without CSS" do
      it "returns content as-is" do
        result = helper.style_capsule do
          "<div>No CSS here</div>"
        end
        expect(result).to include("No CSS here")
        expect(result).not_to include("<style")
      end
    end
  end

  describe "#register_stylesheet" do
    it "registers a stylesheet" do
      helper.register_stylesheet("stylesheets/my_component")
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end

    it "registers with namespace" do
      helper.register_stylesheet("stylesheets/admin/dashboard", namespace: :admin)
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :admin)).to be true
    end
  end

  describe "#stylesheet_registrymap_tags" do
    before do
      StyleCapsule::StylesheetRegistry.clear
    end

    it "renders registered stylesheets" do
      helper.register_stylesheet("stylesheets/my_component")
      result = helper.stylesheet_registrymap_tags
      expect(result).to be_a(String)
      # File registrations persist in manifest (process-wide), so any? returns true
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
      # But inline CSS should be cleared (request-scoped)
      expect(StyleCapsule::StylesheetRegistry.request_inline_stylesheets).to be_empty
    end

    it "renders specific namespace" do
      helper.register_stylesheet("stylesheets/admin", namespace: :admin)
      helper.register_stylesheet("stylesheets/user", namespace: :user)
      result = helper.stylesheet_registrymap_tags(namespace: :admin)
      expect(result).to be_a(String)
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :user)).to be true # User namespace should remain
    end

    it "handles empty namespace string" do
      helper.register_stylesheet("stylesheets/test", namespace: "")
      result = helper.stylesheet_registrymap_tags(namespace: "")
      expect(result).to be_a(String)
    end
  end

  describe "edge cases" do
    it "handles nil CSS content gracefully" do
      result = helper.style_capsule(nil) do
        "<div>Content</div>"
      end
      expect(result).to include("Content")
      expect(result).not_to include("<style")
    end

    it "handles empty CSS content" do
      result = helper.style_capsule("") do
        "<div>Content</div>"
      end
      expect(result).to include("Content")
      expect(result).not_to include("<style")
    end

    it "handles CSS without content block" do
      css = ".test { color: red; }"
      result = helper.style_capsule(css)
      expect(result).to include("<style")
      expect(result).to include("[data-capsule=")
    end

    it "handles style_capsule with no arguments and no block" do
      result = helper.style_capsule
      expect(result).to eq("")
    end
  end
end
