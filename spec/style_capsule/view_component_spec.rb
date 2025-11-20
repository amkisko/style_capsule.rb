# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe StyleCapsule::ViewComponent do
  before do
    skip "view_component not available" unless defined?(ViewComponent::Base)
  end

  let(:view_context_double) do
    instance_double("ActionView::Base",
      content_tag: "<div>content</div>",
      stylesheet_link_tag: '<link rel="stylesheet">')
  end

  let(:component_class) do
    Class.new(ViewComponent::Base) do
      include StyleCapsule::ViewComponent

      attr_accessor :view_context_double

      def initialize(view_context: nil)
        @view_context_double = view_context
      end

      def helpers
        @view_context_double
      end

      def component_styles
        <<~CSS
          .section { color: red; }
          .heading:hover { opacity: 0.8; }
        CSS
      end

      def call
        helpers.content_tag(:div, "Content", class: "section")
      end
    end
  end

  let(:component) do
    instance = component_class.new
    instance.view_context_double = view_context_double
    instance
  end

  before do
    StyleCapsule::StylesheetRegistry.clear
    allow(view_context_double).to receive(:content_tag) do |tag, content = nil, options = {}, &block|
      if block_given?
        content = block.call
      end
      content ||= ""
      attrs = if options.is_a?(Hash) && !options.empty?
        if options[:data]
          data_attrs = options[:data].map { |k, v| %(data-#{k}="#{v}") }.join(" ")
          other_attrs = options.except(:data).map { |k, v| %(#{k}="#{v}") }.join(" ")
          [data_attrs, other_attrs].reject(&:empty?).join(" ")
        else
          options.map { |k, v| %(#{k}="#{v}") }.join(" ")
        end
      else
        ""
      end
      attrs = " #{attrs}" unless attrs.empty?
      "<#{tag}#{attrs}>#{content}</#{tag}>"
    end
  end

  describe "inclusion" do
    it "extends class with ClassMethods" do
      expect(component_class).to respond_to(:capsule_id)
      expect(component_class).to respond_to(:head_injection!)
      expect(component_class).to respond_to(:css_cache)
    end

    it "prepends CallWrapper" do
      expect(component_class.ancestors).to include(StyleCapsule::ViewComponent::CallWrapper)
    end
  end

  describe "#component_capsule" do
    it "generates a scope ID based on class name" do
      scope = component.component_capsule
      expect(scope).to be_a(String)
      expect(scope.length).to eq(8)
      expect(scope).to start_with("a")
    end

    it "uses custom scope ID when set" do
      component_class.capsule_id("test-123")
      expect(component.component_capsule).to eq("test-123")
    end

    it "shares scope ID across instances of same class" do
      instance1 = component_class.new
      instance1.view_context_double = view_context_double
      instance2 = component_class.new
      instance2.view_context_double = view_context_double
      expect(instance1.component_capsule).to eq(instance2.component_capsule)
    end
  end

  describe "CSS scoping" do
    it "scopes CSS selectors" do
      component.component_capsule
      # Access private method via send for testing
      scoped_css = component.send(:scope_css, component.component_styles)
      expect(scoped_css).to include("[data-capsule=")
      expect(scoped_css).to include(".section")
    end

    it "caches scoped CSS per component class" do
      scope = component.component_capsule
      scoped_css1 = component.send(:scope_css, component.component_styles)
      scoped_css2 = component.send(:scope_css, component.component_styles)
      expect(scoped_css1).to eq(scoped_css2)
      expect(component_class.css_cache).to have_key("#{component_class.name}:#{scope}:selector_patching")
    end

    describe "css_scoping_strategy" do
      it "defaults to :selector_patching" do
        expect(component_class.css_scoping_strategy).to eq(:selector_patching)
      end

      it "can be set to :nesting" do
        component_class.css_scoping_strategy(:nesting)
        expect(component_class.css_scoping_strategy).to eq(:nesting)
      end

      it "uses selector patching strategy by default" do
        component.component_capsule
        scoped_css = component.send(:scope_css, component.component_styles)
        # Selector patching adds prefix to each selector
        expect(scoped_css).to include('[data-capsule="')
        expect(scoped_css).to include('"] .section')
      end

      it "uses nesting strategy when configured" do
        component_class.css_scoping_strategy(:nesting)
        component.component_capsule
        scoped_css = component.send(:scope_css, component.component_styles)
        # Nesting wraps entire CSS
        expect(scoped_css).to start_with('[data-capsule="')
        expect(scoped_css).to include('"] {')
        expect(scoped_css).to include(".section { color: red; }")
        expect(scoped_css).to end_with("\n}")
      end

      it "caches scoped CSS separately for different strategies" do
        scope = component.component_capsule

        # First with selector_patching
        scoped_css1 = component.send(:scope_css, component.component_styles)
        expect(component_class.css_cache).to have_key("#{component_class.name}:#{scope}:selector_patching")

        # Then with nesting
        component_class.css_scoping_strategy(:nesting)
        scoped_css2 = component.send(:scope_css, component.component_styles)
        expect(component_class.css_cache).to have_key("#{component_class.name}:#{scope}:nesting")

        # Results should be different
        expect(scoped_css1).not_to eq(scoped_css2)
      end

      it "rejects invalid strategy" do
        expect {
          component_class.css_scoping_strategy(:invalid)
        }.to raise_error(ArgumentError, /must be :selector_patching or :nesting/)
      end

      it "inherits strategy from parent class" do
        # Create a base class with nesting strategy
        base_class = Class.new(ViewComponent::Base) do
          include StyleCapsule::ViewComponent

          css_scoping_strategy :nesting

          attr_accessor :view_context_double

          def initialize(view_context: nil)
            @view_context_double = view_context
          end

          def helpers
            @view_context_double
          end
        end

        # Create a child class that doesn't set its own strategy
        child_class = Class.new(base_class) do
          def component_styles
            ".test { color: red; }"
          end
        end

        # Child should inherit nesting strategy from parent
        expect(child_class.css_scoping_strategy).to eq(:nesting)

        # Verify it actually uses nesting when scoping
        child = child_class.new(view_context: view_context_double)
        scoped_css = child.send(:scope_css, child.component_styles)
        expect(scoped_css).to start_with('[data-capsule="')
        expect(scoped_css).to include('"] {')
        expect(scoped_css).to include(".test { color: red; }")
        expect(scoped_css).to end_with("\n}")
      end

      it "allows child class to override parent strategy" do
        # Create a base class with nesting strategy
        base_class = Class.new(ViewComponent::Base) do
          include StyleCapsule::ViewComponent

          css_scoping_strategy :nesting

          attr_accessor :view_context_double

          def initialize(view_context: nil)
            @view_context_double = view_context
          end

          def helpers
            @view_context_double
          end
        end

        # Create a child class that overrides with selector_patching
        child_class = Class.new(base_class) do
          css_scoping_strategy :selector_patching

          def component_styles
            ".test { color: red; }"
          end
        end

        # Child should use its own strategy, not parent's
        expect(child_class.css_scoping_strategy).to eq(:selector_patching)
        expect(base_class.css_scoping_strategy).to eq(:nesting)

        # Verify it uses selector_patching when scoping
        child = child_class.new(view_context: view_context_double)
        scoped_css = child.send(:scope_css, child.component_styles)
        expect(scoped_css).to include('[data-capsule="')
        expect(scoped_css).to include('"] .test')
        expect(scoped_css).not_to include('"] {')
      end
    end
  end

  describe "head injection" do
    it "renders styles in body by default" do
      expect(component_class.head_injection?).to be false
    end

    it "registers for head injection when enabled" do
      component_class.head_injection!
      expect(component_class.head_injection?).to be true
    end

    it "supports namespace for head injection" do
      component_class.head_injection!
      component_class.stylesheet_namespace(:admin)
      expect(component_class.stylesheet_namespace).to eq(:admin)
    end

    it "registers inline CSS for head injection when enabled" do
      component_class.head_injection!
      StyleCapsule::StylesheetRegistry.clear

      instance = component_class.new
      instance.view_context_double = view_context_double
      instance.send(:render_capsule_styles)

      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end

    it "renders style tag in body when head injection is disabled" do
      StyleCapsule::StylesheetRegistry.clear
      instance = component_class.new
      instance.view_context_double = view_context_double

      output = instance.send(:render_capsule_styles)

      expect(output).to include("<style")
      expect(output).to include("text/css")
      # Inline CSS is registered for head injection, so registry has content
      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end
  end

  describe "class methods" do
    describe ".capsule_id" do
      it "sets custom scope ID" do
        component_class.capsule_id("custom-123")
        expect(component_class.custom_capsule_id).to eq("custom-123")
        expect(component.component_capsule).to eq("custom-123")
      end
    end

    describe ".css_cache" do
      it "returns a hash" do
        expect(component_class.css_cache).to be_a(Hash)
      end

      it "caches CSS per component class" do
        other_class = Class.new do
          include StyleCapsule::ViewComponent

          def helpers
            instance_double("ActionView::Base")
          end

          def component_styles
            ".other { color: blue; }"
          end
        end

        component.send(:scope_css, component.component_styles)
        other_instance = other_class.new
        other_instance.send(:scope_css, other_instance.component_styles)

        expect(component_class.css_cache).not_to be_empty
        expect(other_class.css_cache).not_to be_empty
        expect(component_class.css_cache).not_to eq(other_class.css_cache)
      end
    end

    describe ".clear_css_cache" do
      it "clears the CSS cache" do
        # Populate cache
        component.send(:scope_css, component.component_styles)
        expect(component_class.css_cache).not_to be_empty

        # Clear cache
        component_class.clear_css_cache
        expect(component_class.css_cache).to be_empty
      end

      it "allows CSS to be reprocessed after clearing" do
        # Populate cache
        scoped_css1 = component.send(:scope_css, component.component_styles)
        expect(component_class.css_cache).not_to be_empty

        # Clear cache
        component_class.clear_css_cache

        # CSS should be reprocessed (not from cache)
        scoped_css2 = component.send(:scope_css, component.component_styles)
        expect(scoped_css1).to eq(scoped_css2)
        expect(component_class.css_cache).not_to be_empty
      end
    end
  end

  describe "#component_styles?" do
    it "returns true when component_styles is defined and present" do
      expect(component.send(:component_styles?)).to be true
    end

    it "returns false when component_styles is not defined" do
      component_without_styles = Class.new do
        include StyleCapsule::ViewComponent

        def helpers
          instance_double("ActionView::Base")
        end
      end.new
      expect(component_without_styles.send(:component_styles?)).to be false
    end

    it "returns false when component_styles is blank" do
      component_with_blank_styles = Class.new do
        include StyleCapsule::ViewComponent

        def helpers
          instance_double("ActionView::Base")
        end

        def component_styles
          ""
        end
      end.new
      expect(component_with_blank_styles.send(:component_styles?)).to be false
    end
  end

  describe "#call wrapper" do
    it "wraps content in scoped div when styles are present" do
      output = component.call
      expect(output).to include("data-capsule=")
      expect(output).to include("Content")
      expect(output).to include("<style")
    end

    it "renders normally when no styles are present" do
      component_without_styles = Class.new do
        include StyleCapsule::ViewComponent

        attr_accessor :view_context_double

        def helpers
          @view_context_double
        end

        def call
          helpers.content_tag(:div, "No styles")
        end
      end.new

      component_without_styles.view_context_double = view_context_double
      allow(view_context_double).to receive(:content_tag).with(:div, "No styles") do
        "<div>No styles</div>"
      end

      output = component_without_styles.call
      expect(output).to include("No styles")
      expect(output).not_to include("data-capsule=")
      expect(output).not_to include("<style")
    end
  end

  describe "class method component_styles" do
    let(:view_context) do
      double("ViewContext").tap do |vc|
        allow(vc).to receive(:content_tag) do |tag, content = nil, options = {}, &block|
          content = block.call if block_given?
          attrs = options.map { |k, v| %(#{k}="#{v}") }.join(" ")
          attrs = " #{attrs}" unless attrs.empty?
          "<#{tag}#{attrs}>#{content}</#{tag}>".html_safe
        end
      end
    end

    let(:component_class_with_class_styles) do
      Class.new(ViewComponent::Base) do
        include StyleCapsule::ViewComponent

        def initialize(view_context: nil, **kwargs)
          @view_context = view_context
        end

        def self.component_styles
          <<~CSS
            .static { color: blue; }
          CSS
        end

        def call
          helpers.content_tag(:div, "Static", class: "static")
        end

        def helpers
          @view_context
        end
      end
    end

    it "uses class method component_styles when defined" do
      component = component_class_with_class_styles.new(view_context: view_context)
      expect(component.send(:component_styles?)).to be true
      expect(component.send(:component_styles_content)).to include(".static")
      expect(component.send(:class_styles_only?)).to be true
    end

    it "prefers instance method over class method" do
      component_class_both = Class.new(ViewComponent::Base) do
        include StyleCapsule::ViewComponent

        def initialize(view_context: nil, **kwargs)
          @view_context = view_context
        end

        def self.component_styles
          ".class-method { color: red; }"
        end

        def component_styles
          ".instance-method { color: green; }"
        end

        def call
          helpers.content_tag(:div, "Both")
        end

        def helpers
          @view_context
        end
      end

      component = component_class_both.new(view_context: view_context)
      expect(component.send(:component_styles_content)).to include(".instance-method")
      expect(component.send(:component_styles_content)).not_to include(".class-method")
      expect(component.send(:class_styles_only?)).to be false
    end

    it "handles NoMethodError when class method raises error" do
      component_class_error = Class.new(ViewComponent::Base) do
        include StyleCapsule::ViewComponent

        def initialize(view_context: nil, **kwargs)
          @view_context = view_context
        end

        def self.respond_to?(method, include_private = false)
          return true if method == :component_styles
          super
        end

        def self.component_styles
          raise NoMethodError, "Method not available"
        end

        def call
          helpers.content_tag(:div, "Error")
        end

        def helpers
          @view_context
        end
      end

      component = component_class_error.new(view_context: view_context)
      # Should handle the error gracefully
      expect(component.send(:class_styles?)).to be false
    end

    context "with file caching" do
      before do
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

      it "allows file caching for class method component_styles" do
        component_class_file = Class.new(ViewComponent::Base) do
          include StyleCapsule::ViewComponent

          def initialize(view_context: nil, **kwargs)
            @view_context = view_context
          end

          head_injection!
          inline_cache_strategy :file

          def self.component_styles
            ".file-cached { color: orange; }"
          end

          def call
            helpers.content_tag(:div, "File Cached", class: "file-cached")
          end

          def helpers
            @view_context
          end
        end

        component = component_class_file.new(view_context: view_context)
        expect(component.send(:file_caching_allowed?)).to be true
        component.send(:render_capsule_styles)

        # Should write file
        expect(StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class_file,
          capsule_id: component.component_capsule
        )).to be true
      end

      it "falls back to :none when file caching requested but instance method used" do
        component_class_instance = Class.new(ViewComponent::Base) do
          include StyleCapsule::ViewComponent

          head_injection!
          inline_cache_strategy :file

          def initialize(view_context: nil)
            @view_context = view_context
          end

          def component_styles
            ".instance { color: purple; }"
          end

          def call
            helpers.content_tag(:div, "Instance")
          end

          def helpers
            @view_context
          end
        end

        component = component_class_instance.new(view_context: view_context)
        expect(component.send(:file_caching_allowed?)).to be false
        component.send(:render_capsule_styles)

        # Should not write file, should register inline instead
        expect(StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class_instance,
          capsule_id: component.component_capsule
        )).to be false
        expect(StyleCapsule::StylesheetRegistry.request_inline_stylesheets).not_to be_empty
      end
    end
  end
end
