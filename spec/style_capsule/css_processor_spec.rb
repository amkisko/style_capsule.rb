# frozen_string_literal: true

RSpec.describe StyleCapsule::CssProcessor do
  describe ".scope_selectors" do
    it "scopes simple class selectors" do
      css = ".section { color: red; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .section')
    end

    it "scopes multiple selectors" do
      css = ".a, .b { color: red; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .a')
      expect(result).to include('[data-capsule="abc123"] .b')
    end

    it "scopes pseudo-classes" do
      css = ".button:hover { opacity: 0.8; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .button:hover')
    end

    it "handles :host selector" do
      css = ":host { display: block; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"]')
      expect(result).not_to include(":host")
    end

    it "handles :host(.class) selector" do
      css = ":host(.active) { color: blue; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"].active')
    end

    it "handles :host-context selector" do
      css = ":host-context(.theme-dark) { background: black; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .theme-dark')
    end

    it "preserves @media queries" do
      css = <<~CSS
        @media (max-width: 768px) {
          .section { color: red; }
        }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include("@media")
      expect(result).to include('[data-capsule="abc123"] .section')
    end

    it "does not double-scope already scoped selectors" do
      css = '[data-capsule="abc123"].section { color: red; }'
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to eq(css)
    end

    it "handles empty selectors" do
      css = "   { color: red; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to eq(css)
    end

    it "handles complex nested rules" do
      css = <<~CSS
        .container { padding: 10px; }
        .container .item { margin: 5px; }
        .container .item:hover { background: yellow; }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .container')
      expect(result).to include('[data-capsule="abc123"] .container .item')
      expect(result).to include('[data-capsule="abc123"] .container .item:hover')
    end

    it "handles ID selectors" do
      css = "#header { padding: 10px; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] #header')
    end

    it "handles element selectors" do
      css = "div { margin: 0; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] div')
    end

    it "handles attribute selectors" do
      css = "[data-test] { display: block; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] [data-test]')
    end

    it "handles pseudo-elements" do
      css = ".item::before { content: ''; }"
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .item::before')
    end

    it "handles @keyframes" do
      css = <<~CSS
        @keyframes fade {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        .fade { animation: fade 1s; }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include("@keyframes")
      expect(result).to include('[data-capsule="abc123"] .fade')
    end

    it "handles multiple rules with different selectors" do
      css = <<~CSS
        .class { color: red; }
        #id { padding: 10px; }
        div.element { margin: 0; }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .class')
      expect(result).to include('[data-capsule="abc123"] #id')
      expect(result).to include('[data-capsule="abc123"] div.element')
    end

    it "preserves whitespace in CSS" do
      css = "  .test  {  color: red;  }  "
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"]')
      expect(result).to include(".test")
    end

    it "strips CSS comments before processing (simple approach)" do
      css = <<~CSS
        /* This is a comment */
        .section { color: red; }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .section')
      # Comments are stripped (acceptable for production CSS)
      expect(result).not_to include("/* This is a comment */")
    end

    it "strips CSS comments that look like selectors" do
      css = <<~CSS
        /* .fake-selector { */
        .real-selector { color: red; }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      # Should scope the real selector, comment is stripped
      expect(result).to include('[data-capsule="abc123"] .real-selector')
      expect(result).not_to include("/* .fake-selector { */")
    end

    it "strips multi-line comments" do
      css = <<~CSS
        /*
         * Multi-line comment
         * .fake { }
         */
        .real { color: red; }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include('[data-capsule="abc123"] .real')
      # Comments are stripped
      expect(result).not_to include("Multi-line comment")
    end

    it "handles comments inside @media queries (stripped but selectors still scoped)" do
      css = <<~CSS
        @media (max-width: 768px) {
          /* Comment inside media query */
          .section { color: red; }
        }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      expect(result).to include("@media")
      expect(result).to include('[data-capsule="abc123"] .section')
      # Comments are stripped
      expect(result).not_to include("Comment inside media query")
    end

    it "strips comments but preserves string content" do
      css = <<~CSS
        /* This is a comment */
        .class {
          content: "string value";
        }
      CSS
      result = described_class.scope_selectors(css, "abc123")
      # Comments are stripped, but string content is preserved
      expect(result).not_to include("/* This is a comment */")
      expect(result).to include('"string value"')
      expect(result).to include('[data-capsule="abc123"] .class')
    end

    it "handles empty CSS gracefully" do
      expect(described_class.scope_selectors("", "abc123")).to eq("")
      expect(described_class.scope_selectors(nil, "abc123")).to be_nil
      expect(described_class.scope_selectors("   ", "abc123")).to eq("   ")
    end

    it "rejects CSS content that exceeds maximum size" do
      large_css = "a" * (StyleCapsule::CssProcessor::MAX_CSS_SIZE + 1)
      expect {
        described_class.scope_selectors(large_css, "abc123")
      }.to raise_error(ArgumentError, /exceeds maximum size/)
    end

    it "accepts CSS content at maximum size" do
      max_size_css = "a" * StyleCapsule::CssProcessor::MAX_CSS_SIZE
      expect {
        described_class.scope_selectors(max_size_css, "abc123")
      }.not_to raise_error
    end

    it "rejects invalid capsule_id (non-string)" do
      expect {
        described_class.scope_selectors(".test { color: red; }", 123)
      }.to raise_error(ArgumentError, /capsule_id must be a String/)
    end

    it "rejects capsule_id with unsafe characters" do
      expect {
        described_class.scope_selectors(".test { color: red; }", "capsule<script>")
      }.to raise_error(ArgumentError, /Invalid capsule_id/)
    end

    it "rejects capsule_id with path traversal" do
      expect {
        described_class.scope_selectors(".test { color: red; }", "../etc/passwd")
      }.to raise_error(ArgumentError, /Invalid capsule_id/)
    end

    it "rejects scope_id that is too long" do
      long_scope = "a" * 101
      expect {
        described_class.scope_selectors(".test { color: red; }", long_scope)
      }.to raise_error(ArgumentError, /too long/)
    end

    it "rejects empty scope_id" do
      expect {
        described_class.scope_selectors(".test { color: red; }", "")
      }.to raise_error(ArgumentError, /cannot be empty/)
    end

    it "accepts valid scope_id with alphanumeric characters" do
      expect {
        described_class.scope_selectors(".test { color: red; }", "abc123")
      }.not_to raise_error
    end

    it "accepts valid scope_id with hyphens and underscores" do
      expect {
        described_class.scope_selectors(".test { color: red; }", "scope-id_123")
      }.not_to raise_error
    end
  end

  describe ".scope_with_nesting" do
    it "wraps simple CSS in nesting selector" do
      css = ".section { color: red; }"
      result = described_class.scope_with_nesting(css, "abc123")
      expected = <<~CSS.chomp
        [data-capsule="abc123"] {
        .section { color: red; }
        }
      CSS
      expect(result).to eq(expected)
    end

    it "wraps multiple CSS rules in nesting selector" do
      css = <<~CSS
        .section { color: red; }
        .heading:hover { opacity: 0.8; }
      CSS
      result = described_class.scope_with_nesting(css, "abc123")
      expect(result).to start_with('[data-capsule="abc123"] {')
      expect(result).to include(".section { color: red; }")
      expect(result).to include(".heading:hover { opacity: 0.8; }")
      expect(result).to end_with("\n}")
    end

    it "preserves all CSS content without modification" do
      css = <<~CSS
        .class { color: red; }
        #id { padding: 10px; }
        div.element { margin: 0; }
        @media (max-width: 768px) {
          .responsive { display: block; }
        }
      CSS
      result = described_class.scope_with_nesting(css, "abc123")
      expect(result).to start_with('[data-capsule="abc123"] {')
      expect(result).to include(".class { color: red; }")
      expect(result).to include("#id { padding: 10px; }")
      expect(result).to include("div.element { margin: 0; }")
      expect(result).to include("@media (max-width: 768px)")
      expect(result).to include(".responsive { display: block; }")
    end

    it "handles empty CSS gracefully" do
      expect(described_class.scope_with_nesting("", "abc123")).to eq("")
      expect(described_class.scope_with_nesting(nil, "abc123")).to be_nil
      expect(described_class.scope_with_nesting("   ", "abc123")).to eq("   ")
    end

    it "rejects CSS content that exceeds maximum size" do
      large_css = "a" * (StyleCapsule::CssProcessor::MAX_CSS_SIZE + 1)
      expect {
        described_class.scope_with_nesting(large_css, "abc123")
      }.to raise_error(ArgumentError, /exceeds maximum size/)
    end

    it "accepts CSS content at maximum size" do
      max_size_css = "a" * StyleCapsule::CssProcessor::MAX_CSS_SIZE
      expect {
        described_class.scope_with_nesting(max_size_css, "abc123")
      }.not_to raise_error
    end

    it "rejects invalid capsule_id (non-string)" do
      expect {
        described_class.scope_with_nesting(".test { color: red; }", 123)
      }.to raise_error(ArgumentError, /capsule_id must be a String/)
    end

    it "rejects capsule_id with unsafe characters" do
      expect {
        described_class.scope_with_nesting(".test { color: red; }", "capsule<script>")
      }.to raise_error(ArgumentError, /Invalid capsule_id/)
    end

    it "rejects capsule_id with path traversal" do
      expect {
        described_class.scope_with_nesting(".test { color: red; }", "../etc/passwd")
      }.to raise_error(ArgumentError, /Invalid capsule_id/)
    end

    it "rejects scope_id that is too long" do
      long_scope = "a" * 101
      expect {
        described_class.scope_with_nesting(".test { color: red; }", long_scope)
      }.to raise_error(ArgumentError, /too long/)
    end

    it "rejects empty scope_id" do
      expect {
        described_class.scope_with_nesting(".test { color: red; }", "")
      }.to raise_error(ArgumentError, /cannot be empty/)
    end

    it "accepts valid scope_id with alphanumeric characters" do
      expect {
        described_class.scope_with_nesting(".test { color: red; }", "abc123")
      }.not_to raise_error
    end

    it "accepts valid scope_id with hyphens and underscores" do
      expect {
        described_class.scope_with_nesting(".test { color: red; }", "scope-id_123")
      }.not_to raise_error
    end
  end
end
