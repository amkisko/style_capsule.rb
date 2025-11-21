# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Integration tests for Phlex components with StyleCapsule
# These tests use the actual phlex-rails gem to verify real-world compatibility
RSpec.describe "StyleCapsule Phlex Integration", type: :integration do
  before do
    skip "phlex-rails not available" unless defined?(Phlex::HTML)
  end

  let(:view_context_double) do
    double("ViewContext").tap do |vc|
      allow(vc).to receive(:stylesheet_link_tag).and_return('<link rel="stylesheet">')
      allow(vc).to receive(:content_tag).and_return("<div></div>")
    end
  end

  let(:base_component_class) do
    Class.new(Phlex::HTML) do
      include StyleCapsule::PhlexHelper

      attr_accessor :view_context

      def initialize(*args, **kwargs)
        super
      end
    end
  end

  describe "Component with StyleCapsule::Component" do
    let(:component_class) do
      Class.new(base_component_class) do
        include StyleCapsule::Component

        def component_styles
          <<~CSS
            .section { color: red; }
            .heading:hover { opacity: 0.8; }
          CSS
        end

        def view_template
          div(class: "section") do
            h2(class: "heading") { "Hello" }
          end
        end
      end
    end

    it "renders scoped CSS and wrapped content" do
      component = component_class.new
      component.view_context = view_context_double
      output = component.call.to_s.html_safe

      # Should include scoped style tag
      expect(output).to include("<style")
      expect(output).to include("[data-capsule=")
      expect(output).to include(".section")
      expect(output).to include(".heading:hover")

      # Should wrap content in scoped div
      expect(output).to include("data-capsule=")
      expect(output).to include('class="section"')
      expect(output).to include("Hello")
    end

    it "generates consistent scope IDs across instances" do
      instance1 = component_class.new
      instance1.view_context = view_context_double
      instance2 = component_class.new
      instance2.view_context = view_context_double

      scope1 = instance1.component_capsule
      scope2 = instance2.component_capsule

      expect(scope1).to eq(scope2)
      expect(scope1.length).to eq(8)
      expect(scope1).to start_with("a")
    end

    it "scopes CSS selectors correctly" do
      component = component_class.new
      component.view_context = view_context_double
      scope = component.component_capsule
      scoped_css = component.send(:scope_css, component.component_styles)

      expect(scoped_css).to include(%([data-capsule="#{scope}"] .section))
      expect(scoped_css).to include(%([data-capsule="#{scope}"] .heading:hover))
    end

    context "with head rendering" do
      before do
        component_class.stylesheet_registry
        StyleCapsule::StylesheetRegistry.clear
      end

      it "registers CSS for head rendering instead of rendering in body" do
        component = component_class.new
        component.view_context = view_context_double
        output = component.call.to_s

        # Should not include style tag in body
        expect(output).not_to include("<style")

        # Should register for head rendering
        expect(StyleCapsule::StylesheetRegistry.any?).to be true
      end

      it "renders registered stylesheets via helper" do
        component = component_class.new
        component.view_context = view_context_double
        component.call

        # Render via helper
        view_context = double("ViewContext").tap do |vc|
          allow(vc).to receive(:content_tag) do |tag, content = nil, options = {}, &block|
            content = block.call if block_given?
            attrs = options.map { |k, v| %(#{k}="#{v}") }.join(" ")
            attrs = " #{attrs}" unless attrs.empty?
            "<#{tag}#{attrs}>#{content}</#{tag}>".html_safe
          end
          allow(vc).to receive(:stylesheet_link_tag).and_return('<link rel="stylesheet">')
        end
        head_output = StyleCapsule::StylesheetRegistry.render_head_stylesheets(view_context)

        expect(head_output).to include("<style")
        expect(head_output).to include(".section")
      end
    end

    context "with custom scope ID" do
      before do
        component_class.capsule_id("test-scope-123")
      end

      it "uses custom scope ID" do
        component = component_class.new
        component.view_context = view_context_double
        expect(component.component_capsule).to eq("test-scope-123")
      end
    end
  end

  describe "Component without styles" do
    let(:component_class) do
      Class.new(base_component_class) do
        include StyleCapsule::Component

        def view_template
          div { "No styles" }
        end
      end
    end

    it "renders normally without scoping" do
      component = component_class.new
      component.view_context = view_context_double
      output = component.call.to_s

      expect(output).to include("No styles")
      expect(output).not_to include("data-capsule")
      expect(output).not_to include("<style")
    end
  end

  describe "PhlexHelper integration" do
    let(:component_class) do
      Class.new(base_component_class) do
        def view_template
          register_stylesheet("stylesheets/test")
          div { "Content" }
        end
      end
    end

    it "registers stylesheets via helper" do
      StyleCapsule::StylesheetRegistry.clear_manifest
      component = component_class.new
      component.view_context = view_context_double
      component.call

      expect(StyleCapsule::StylesheetRegistry.manifest_files[:default]).not_to be_empty
      expect(StyleCapsule::StylesheetRegistry.manifest_files[:default].first[:file_path]).to eq("stylesheets/test")
    end

    it "renders stylesheet tags via helper" do
      StyleCapsule::StylesheetRegistry.clear_manifest
      component = component_class.new
      component.view_context = view_context_double
      component.call

      output = component.stylesheet_registrymap_tags

      expect(output).to be_a(String)
    end
  end

  describe "Component with cache strategy" do
    let(:component_class) do
      Class.new(base_component_class) do
        include StyleCapsule::Component

        stylesheet_registry cache_strategy: :time, cache_ttl: 3600

        def component_styles
          ".cached { color: blue; }"
        end

        def view_template
          div(class: "cached") { "Cached" }
        end
      end
    end

    before do
      StyleCapsule::StylesheetRegistry.clear_inline_cache
      StyleCapsule::StylesheetRegistry.clear
    end

    it "caches inline CSS" do
      component1 = component_class.new
      component1.view_context = view_context_double
      component1.call

      # First render should cache
      cache_key = "#{component_class.name}:#{component1.component_capsule}"
      expect(StyleCapsule::StylesheetRegistry.inline_cache[cache_key]).not_to be_nil

      # Second render should use cache
      component2 = component_class.new
      component2.view_context = view_context_double
      component2.call

      cached_entry = StyleCapsule::StylesheetRegistry.inline_cache[cache_key]
      expect(cached_entry[:css_content]).to include(".cached")
      expect(cached_entry[:expires_at]).to be_a(Time)
    end
  end

  describe "Component with file-based cache strategy" do
    let(:component_class) do
      klass = Class.new(base_component_class)
      # Give anonymous class a name to avoid nil class name issues
      Object.const_set("FileCachedPhlexComponent_#{klass.object_id}", klass) unless klass.name
      klass.class_eval do
        include StyleCapsule::Component

        stylesheet_registry cache_strategy: :file

        # File caching requires class method component_styles
        def self.component_styles
          ".file-cached { color: orange; }"
        end

        def view_template
          div(class: "file-cached") { "File Cached" }
        end
      end
      klass
    end

    before do
      # Configure file writer for tests
      test_output_dir = Pathname.new(Dir.mktmpdir)
      StyleCapsule::CssFileWriter.configure(
        output_dir: test_output_dir,
        enabled: true
      )
      StyleCapsule::StylesheetRegistry.clear
    end

    after do
      StyleCapsule::CssFileWriter.clear_files
      output_dir = StyleCapsule::CssFileWriter.output_dir
      FileUtils.rm_rf(output_dir) if output_dir && Dir.exist?(output_dir)
    end

    it "writes CSS to file and registers it" do
      component = component_class.new
      component.view_context = view_context_double
      component.call

      # Should write file
      expect(StyleCapsule::CssFileWriter.file_exists?(
        component_class: component_class,
        capsule_id: component.component_capsule
      )).to be true

      # Should register file path in manifest
      expect(StyleCapsule::StylesheetRegistry.manifest_files[:default]).not_to be_empty
      file_path = StyleCapsule::StylesheetRegistry.manifest_files[:default].first[:file_path]
      # File path uses capsule-{capsule_id} pattern (default filename pattern)
      expect(file_path).to include("capsule-")
    end
  end
end
