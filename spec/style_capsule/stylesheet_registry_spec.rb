# frozen_string_literal: true

RSpec.describe StyleCapsule::StylesheetRegistry do
  before do
    # Clear both request-scoped inline CSS and process-wide manifest
    described_class.clear
    described_class.clear_manifest
  end

  describe ".normalize_namespace" do
    it "normalizes nil to default namespace" do
      expect(described_class.normalize_namespace(nil)).to eq(:default)
    end

    it "normalizes empty string to default namespace" do
      expect(described_class.normalize_namespace("")).to eq(:default)
    end

    it "normalizes symbol to symbol" do
      expect(described_class.normalize_namespace(:admin)).to eq(:admin)
    end

    it "normalizes string to symbol" do
      expect(described_class.normalize_namespace("admin")).to eq(:admin)
    end
  end

  describe ".register" do
    it "registers a stylesheet file" do
      described_class.register("stylesheets/my_component")
      stylesheets = described_class.stylesheets_for
      expect(stylesheets.length).to eq(1)
      expect(stylesheets.first[:file_path]).to eq("stylesheets/my_component")
    end

    it "registers with namespace" do
      described_class.register("stylesheets/admin/dashboard", namespace: :admin)
      stylesheets = described_class.stylesheets_for(namespace: :admin)
      expect(stylesheets.length).to eq(1)
      expect(stylesheets.first[:file_path]).to eq("stylesheets/admin/dashboard")
    end

    it "registers with options" do
      described_class.register("stylesheets/my_component", "data-turbo-track": "reload")
      stylesheets = described_class.stylesheets_for
      expect(stylesheets.first[:options][:"data-turbo-track"]).to eq("reload")
    end
  end

  describe ".register_inline" do
    it "registers inline CSS" do
      css = ".section { color: red; }"
      described_class.register_inline(css)
      stylesheets = described_class.stylesheets_for
      expect(stylesheets.length).to eq(1)
      expect(stylesheets.first[:type]).to eq(:inline)
      expect(stylesheets.first[:css_content]).to eq(css)
    end

    it "registers inline CSS with namespace" do
      css = ".section { color: red; }"
      described_class.register_inline(css, namespace: :admin, capsule_id: "abc123")
      stylesheets = described_class.stylesheets_for(namespace: :admin)
      expect(stylesheets.first[:capsule_id]).to eq("abc123")
    end
  end

  describe ".stylesheets_for" do
    it "returns empty array when no stylesheets registered" do
      expect(described_class.stylesheets_for).to eq([])
    end

    it "returns stylesheets for default namespace" do
      described_class.register("stylesheets/one")
      described_class.register("stylesheets/two")
      expect(described_class.stylesheets_for.length).to eq(2)
    end

    it "returns stylesheets for specific namespace" do
      described_class.register("stylesheets/admin", namespace: :admin)
      described_class.register("stylesheets/user", namespace: :user)
      expect(described_class.stylesheets_for(namespace: :admin).length).to eq(1)
      expect(described_class.stylesheets_for(namespace: :user).length).to eq(1)
    end
  end

  describe ".clear" do
    it "clears only request-scoped inline CSS, not process-wide manifest" do
      described_class.register("stylesheets/one")
      described_class.register_inline(".inline { color: red; }")
      described_class.clear
      # File should still be in manifest
      expect(described_class.stylesheets_for.length).to eq(1)
      expect(described_class.stylesheets_for.first[:file_path]).to eq("stylesheets/one")
      # Inline CSS should be cleared
      expect(described_class.request_inline_stylesheets).to be_empty
    end

    it "clears only specific namespace inline CSS" do
      described_class.register("stylesheets/one")
      described_class.register_inline(".inline { color: red; }", namespace: :admin)
      described_class.clear(namespace: :admin)
      # File should still be in manifest
      expect(described_class.stylesheets_for.length).to eq(1)
      # Inline CSS should be cleared
      expect(described_class.request_inline_stylesheets[:admin]).to be_nil
    end
  end

  describe ".clear_manifest" do
    it "clears process-wide manifest" do
      described_class.register("stylesheets/one")
      described_class.register("stylesheets/two", namespace: :admin)
      expect(described_class.manifest_files[:default]).not_to be_empty
      expect(described_class.manifest_files[:admin]).not_to be_empty

      described_class.clear_manifest
      expect(described_class.manifest_files).to be_empty
    end

    it "clears only specific namespace from manifest" do
      described_class.register("stylesheets/one")
      described_class.register("stylesheets/two", namespace: :admin)
      described_class.clear_manifest(namespace: :admin)
      expect(described_class.manifest_files[:default]).not_to be_empty
      expect(described_class.manifest_files[:admin]).to be_nil
    end
  end

  describe "process-wide manifest behavior" do
    it "persists file registrations across clear calls" do
      described_class.register("stylesheets/persistent")
      expect(described_class.stylesheets_for.length).to eq(1)

      # Clear request-scoped inline CSS (should not affect manifest)
      described_class.clear
      expect(described_class.stylesheets_for.length).to eq(1)
      expect(described_class.stylesheets_for.first[:file_path]).to eq("stylesheets/persistent")
    end

    it "deduplicates file registrations in manifest" do
      described_class.register("stylesheets/duplicate")
      described_class.register("stylesheets/duplicate")
      # Should only have one entry (Set deduplicates)
      expect(described_class.manifest_files[:default].length).to eq(1)
    end
  end

  describe ".any?" do
    it "returns false when no stylesheets registered" do
      expect(described_class.any?).to be false
    end

    it "returns true when stylesheets are registered" do
      described_class.register("stylesheets/one")
      expect(described_class.any?).to be true
    end

    it "checks specific namespace" do
      described_class.register("stylesheets/admin", namespace: :admin)
      expect(described_class.any?(namespace: :admin)).to be true
      expect(described_class.any?(namespace: :user)).to be false
    end
  end

  describe ".render_head_stylesheets" do
    let(:view_context) { double("ViewContext") }

    context "with view context" do
      before do
        allow(view_context).to receive(:stylesheet_link_tag).and_return('<link rel="stylesheet">')
        allow(view_context).to receive(:content_tag).and_return("<style></style>")
      end

      it "renders file-based stylesheets" do
        described_class.register("stylesheets/my_component")
        result = described_class.render_head_stylesheets(view_context)
        expect(result).to include("stylesheet")
        # File registrations persist in manifest (process-wide), so any? returns true
        expect(described_class.any?).to be true
        # But inline CSS should be cleared (request-scoped)
        expect(described_class.request_inline_stylesheets).to be_empty
      end

      it "renders inline stylesheets" do
        css = ".section { color: red; }"
        described_class.register_inline(css)
        allow(view_context).to receive(:content_tag).with(:style, anything, type: "text/css").and_return("<style>.section { color: red; }</style>")
        result = described_class.render_head_stylesheets(view_context)
        expect(result).to include("style")
        expect(described_class.any?).to be false
      end

      it "renders specific namespace" do
        described_class.register("stylesheets/admin", namespace: :admin)
        described_class.register("stylesheets/user", namespace: :user)
        result = described_class.render_head_stylesheets(view_context, namespace: :admin)
        expect(result).to include("stylesheet")
        expect(described_class.stylesheets_for(namespace: :user).length).to eq(1) # User namespace should remain
      end
    end

    context "without view context" do
      it "renders file-based stylesheets with fallback HTML" do
        described_class.register("stylesheets/my_component")
        result = described_class.render_head_stylesheets(nil)
        expect(result).to include('<link rel="stylesheet"')
        expect(result).to include("/assets/stylesheets/my_component.css")
      end

      it "renders inline stylesheets with fallback HTML" do
        css = ".section { color: red; }"
        described_class.register_inline(css)
        result = described_class.render_head_stylesheets(nil)
        expect(result).to include('<style type="text/css">')
        expect(result).to include(css)
      end
    end

    it "returns empty string when no stylesheets" do
      result = described_class.render_head_stylesheets(view_context)
      expect(result).to eq("".html_safe)
    end

    it "handles multiple inline stylesheets" do
      described_class.register_inline(".one { color: red; }")
      described_class.register_inline(".two { color: blue; }")
      allow(view_context).to receive(:content_tag).and_return("<style></style>")
      result = described_class.render_head_stylesheets(view_context)
      expect(result).to include("style")
      expect(described_class.any?).to be false
    end

    it "handles mixed file and inline stylesheets" do
      described_class.register("stylesheets/one")
      described_class.register_inline(".two { color: blue; }")
      allow(view_context).to receive(:stylesheet_link_tag).and_return('<link rel="stylesheet">')
      allow(view_context).to receive(:content_tag).and_return("<style></style>")
      result = described_class.render_head_stylesheets(view_context)
      expect(result).to include("stylesheet")
      expect(result).to include("style")
    end
  end

  describe ".render_file_stylesheet" do
    it "uses stylesheet_link_tag when view_context available" do
      view_context = double("ViewContext")
      allow(view_context).to receive(:stylesheet_link_tag).and_return("<link>")
      stylesheet = {file_path: "stylesheets/test", options: {}}
      result = described_class.send(:render_file_stylesheet, stylesheet, view_context)
      # Empty hash with **options doesn't pass a second argument
      expect(view_context).to have_received(:stylesheet_link_tag).with("stylesheets/test")
      expect(result).to eq("<link>")
    end

    it "falls back to HTML when view_context not available" do
      stylesheet = {file_path: "stylesheets/test", options: {}}
      result = described_class.send(:render_file_stylesheet, stylesheet, nil)
      expect(result).to include('<link rel="stylesheet"')
      expect(result).to include("/assets/stylesheets/test.css")
    end

    it "includes options in fallback HTML" do
      stylesheet = {file_path: "stylesheets/test", options: {"data-turbo-track": "reload"}}
      result = described_class.send(:render_file_stylesheet, stylesheet, nil)
      expect(result).to include('data-turbo-track="reload"')
    end

    it "falls back when view_context doesn't respond to stylesheet_link_tag" do
      view_context = double("ViewContext")
      allow(view_context).to receive(:respond_to?).with(:stylesheet_link_tag).and_return(false)
      stylesheet = {file_path: "stylesheets/test", options: {}}
      result = described_class.send(:render_file_stylesheet, stylesheet, view_context)
      expect(result).to include('<link rel="stylesheet"')
    end

    it "handles empty options in fallback HTML" do
      stylesheet = {file_path: "stylesheets/test", options: {}}
      result = described_class.send(:render_file_stylesheet, stylesheet, nil)
      # Should not include extra space when options are empty
      expect(result).not_to match(/href="[^"]+"\s+>/)
    end
  end

  describe ".render_inline_stylesheet" do
    it "uses content_tag when view_context available" do
      view_context = double("ViewContext")
      css = ".test { color: red; }"
      stylesheet = {css_content: css}
      result = described_class.send(:render_inline_stylesheet, stylesheet, view_context)
      # Implementation constructs HTML directly, not using content_tag
      expect(result).to include('<style type="text/css">')
      expect(result).to include(css)
      expect(result).to include("</style>")
    end

    it "falls back to HTML when view_context not available" do
      css = ".test { color: red; }"
      stylesheet = {css_content: css}
      result = described_class.send(:render_inline_stylesheet, stylesheet, nil)
      expect(result).to include('<style type="text/css">')
      expect(result).to include(css)
    end

    it "falls back when view_context doesn't respond to content_tag" do
      view_context = double("ViewContext")
      allow(view_context).to receive(:respond_to?).with(:content_tag).and_return(false)
      css = ".test { color: red; }"
      stylesheet = {css_content: css}
      result = described_class.send(:render_inline_stylesheet, stylesheet, view_context)
      expect(result).to include('<style type="text/css">')
      expect(result).to include(css)
    end
  end
end
