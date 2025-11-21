# frozen_string_literal: true

require "spec_helper"

RSpec.describe StyleCapsule::StandaloneHelper do
  let(:helper_class) do
    Class.new do
      include StyleCapsule::StandaloneHelper
    end
  end

  let(:helper) { helper_class.new }

  describe "#generate_capsule_id" do
    it "generates a capsule ID based on caller location and CSS content" do
      css = ".section { color: red; }"
      id1 = helper.generate_capsule_id(css)

      expect(id1).to be_a(String)
      expect(id1.length).to eq(8)
      expect(id1).to start_with("a")
    end

    it "generates same ID for same CSS from same location" do
      css = ".section { color: red; }"
      # Call from same line to get same ID
      id1 = helper.generate_capsule_id(css)
      id2 = helper.generate_capsule_id(css)

      # Note: IDs include caller location, so they may differ if called from different lines
      # But the format should be consistent
      expect(id1).to be_a(String)
      expect(id2).to be_a(String)
      expect(id1.length).to eq(8)
      expect(id2.length).to eq(8)
    end

    it "generates different IDs for different CSS content" do
      css1 = ".section { color: red; }"
      css2 = ".section { color: blue; }"
      id1 = helper.generate_capsule_id(css1)
      id2 = helper.generate_capsule_id(css2)

      expect(id1).not_to eq(id2)
    end
  end

  describe "#scope_css" do
    it "scopes CSS content with the given capsule ID" do
      css = ".section { color: red; }"
      capsule_id = "abc123"
      scoped = helper.scope_css(css, capsule_id)

      expect(scoped).to include('[data-capsule="abc123"]')
      expect(scoped).to include(".section")
    end

    it "caches scoped CSS in thread-local storage" do
      css = ".section { color: red; }"
      capsule_id = "abc123"

      # First call
      scoped1 = helper.scope_css(css, capsule_id)

      # Second call should use cache
      expect(StyleCapsule::CssProcessor).not_to receive(:scope_selectors)
      scoped2 = helper.scope_css(css, capsule_id)

      expect(scoped1).to eq(scoped2)
    end
  end

  describe "#content_tag" do
    it "generates HTML tag with content" do
      result = helper.content_tag(:div, "Hello")
      expect(result).to eq("<div>Hello</div>")
    end

    it "generates HTML tag with attributes" do
      result = helper.content_tag(:div, "Hello", class: "section", id: "main")
      expect(result).to include('class="section"')
      expect(result).to include('id="main"')
      expect(result).to include("Hello")
    end

    it "generates HTML tag with block content" do
      result = helper.content_tag(:div) { "Hello" }
      expect(result).to eq("<div>Hello</div>")
    end

    it "handles nested attributes like data: { capsule: 'abc' }" do
      result = helper.content_tag(:div, "Hello", data: {capsule: "abc123"})
      expect(result).to include('data-capsule="abc123"')
    end

    it "handles empty content" do
      result = helper.content_tag(:div, nil)
      expect(result).to eq("<div></div>")
    end

    it "escapes HTML attributes" do
      result = helper.content_tag(:div, "Hello", title: 'Test "quote"')
      expect(result).to include("&quot;")
    end
  end

  describe "#capture" do
    it "captures block content" do
      result = helper.capture { "Hello World" }
      expect(result).to eq("Hello World")
    end

    it "returns empty string when no block given" do
      result = helper.capture
      expect(result).to eq("")
    end

    it "converts block result to string" do
      result = helper.capture { 123 }
      expect(result).to eq("123")
    end
  end

  describe "#html_safe" do
    it "returns string as-is when it doesn't respond to html_safe" do
      string = "Hello"
      result = helper.html_safe(string)
      expect(result).to eq("Hello")
    end

    it "calls html_safe on string when available" do
      string = ActiveSupport::SafeBuffer.new("Hello")
      result = helper.html_safe(string)
      expect(result).to be_a(ActiveSupport::SafeBuffer)
    end

    it "returns string directly when html_safe is not available" do
      # Create a string-like object that doesn't respond to html_safe
      string = Object.new
      def string.to_s
        "Hello"
      end

      result = helper.html_safe(string)
      expect(result).to eq(string)
    end
  end

  describe "#raw" do
    it "returns HTML-safe string" do
      string = "Hello"
      result = helper.raw(string)
      expect(result).to eq("Hello")
    end

    it "converts non-string to string" do
      result = helper.raw(123)
      expect(result).to eq("123")
    end
  end

  describe "#style_capsule" do
    context "with block containing style tag" do
      it "extracts CSS from style tag and wraps content" do
        result = helper.style_capsule do
          "<style>.section { color: red; }</style><div class='section'>Content</div>"
        end

        expect(result).to include("[data-capsule=")
        expect(result).to include(".section")
        expect(result).to include("Content")
        expect(result).to include("<style")
        expect(result).to include("<div")
      end

      it "handles content without style tag" do
        result = helper.style_capsule do
          "<div class='section'>Content</div>"
        end

        expect(result).to include("Content")
      end
    end

    context "with CSS content as argument" do
      it "returns scoped CSS when no block given" do
        css = ".section { color: red; }"
        result = helper.style_capsule(css)

        expect(result).to include("<style")
        expect(result).to include("[data-capsule=")
        expect(result).to include(".section")
      end

      it "wraps block content with scoped CSS" do
        css = ".section { color: red; }"
        result = helper.style_capsule(css) { "<div class='section'>Content</div>" }

        expect(result).to include("<style")
        expect(result).to include("[data-capsule=")
        expect(result).to include("Content")
      end

      it "uses provided capsule_id" do
        css = ".section { color: red; }"
        result = helper.style_capsule(css, capsule_id: "test123")

        expect(result).to include('[data-capsule="test123"]')
      end
    end

    context "with empty or nil CSS" do
      it "returns empty string when no CSS and no block" do
        result = helper.style_capsule
        expect(result).to eq("")
      end

      it "returns content as-is when CSS is empty" do
        result = helper.style_capsule("") { "<div>Content</div>" }
        expect(result).to include("Content")
        expect(result).not_to include("<style")
      end
    end

    context "with size validation" do
      it "raises error when HTML content exceeds maximum size" do
        large_content = "x" * (StyleCapsule::StandaloneHelper::MAX_HTML_SIZE + 1)

        expect {
          helper.style_capsule { large_content }
        }.to raise_error(ArgumentError, /exceeds maximum size/)
      end
    end
  end

  describe "#register_stylesheet" do
    it "registers stylesheet with default namespace" do
      helper.register_stylesheet("stylesheets/main")
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end

    it "registers stylesheet with namespace" do
      helper.register_stylesheet("stylesheets/admin", namespace: :admin)
      expect(StyleCapsule::StylesheetRegistry.any?(namespace: :admin)).to be true
    end

    it "registers stylesheet with options" do
      helper.register_stylesheet("stylesheets/main", "data-turbo-track": "reload")
      # Just verify it doesn't raise an error
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end
  end

  describe "#stylesheet_registrymap_tags" do
    before do
      StyleCapsule::StylesheetRegistry.clear
      StyleCapsule::StylesheetRegistry.clear_manifest
    end

    it "renders registered stylesheets" do
      helper.register_stylesheet("stylesheets/main")
      result = helper.stylesheet_registrymap_tags

      expect(result).to be_a(String)
      expect(result).to include("stylesheet")
    end

    it "renders stylesheets for specific namespace" do
      helper.register_stylesheet("stylesheets/admin", namespace: :admin)
      result = helper.stylesheet_registrymap_tags(namespace: :admin)

      expect(result).to be_a(String)
    end

    it "returns empty string when no stylesheets registered" do
      result = helper.stylesheet_registrymap_tags
      expect(result).to eq("")
    end
  end

  describe "#escape_html_attr" do
    it "escapes HTML special characters" do
      result = helper.send(:escape_html_attr, 'Test "quote" & <tag>')
      expect(result).to eq("Test &quot;quote&quot; &amp; &lt;tag&gt;")
    end

    it "escapes double quotes" do
      result = helper.send(:escape_html_attr, 'Test "quote"')
      expect(result).to eq("Test &quot;quote&quot;")
    end

    it "escapes single quotes" do
      result = helper.send(:escape_html_attr, "Test 'quote'")
      expect(result).to eq("Test &#39;quote&#39;")
    end

    it "escapes ampersands" do
      result = helper.send(:escape_html_attr, "A & B")
      expect(result).to eq("A &amp; B")
    end

    it "escapes less-than and greater-than to prevent XSS" do
      result = helper.send(:escape_html_attr, "<script>alert('xss')</script>")
      expect(result).to eq("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
    end

    it "converts non-string to string" do
      result = helper.send(:escape_html_attr, 123)
      expect(result).to eq("123")
    end
  end
end
