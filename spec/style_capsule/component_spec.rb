# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe StyleCapsule::Component do
  let(:component_class) do
    Class.new do
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

      # Mock Phlex methods
      def div(options = {}, &block)
        "<div#{format_options(options)}>#{block.call if block_given?}</div>"
      end

      def h2(options = {}, &block)
        "<h2#{format_options(options)}>#{block.call if block_given?}</h2>"
      end

      def style(options = {}, &block)
        attrs = if options.is_a?(Hash) && !options.empty?
          options.map { |k, v| %( #{k}="#{v}") }.join
        else
          ""
        end
        "<style#{attrs}>#{block.call if block_given?}</style>"
      end

      def raw(content)
        content
      end

      private

      def format_options(options)
        return "" if options.empty?
        options.map { |k, v| %( #{k}="#{v}") }.join
      end
    end
  end

  let(:component) { component_class.new }

  describe "inclusion" do
    it "extends class with ClassMethods" do
      expect(component_class).to respond_to(:capsule_id)
      expect(component_class).to respond_to(:stylesheet_registry)
      expect(component_class).to respond_to(:css_cache)
    end

    it "prepends ViewTemplateWrapper" do
      expect(component_class.ancestors).to include(StyleCapsule::Component::ViewTemplateWrapper)
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
      instance2 = component_class.new
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
        base_class = Class.new do
          include StyleCapsule::Component

          css_scoping_strategy :nesting
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
        child = child_class.new
        scoped_css = child.send(:scope_css, child.component_styles)
        expect(scoped_css).to start_with('[data-capsule="')
        expect(scoped_css).to include('"] {')
        expect(scoped_css).to include(".test { color: red; }")
        expect(scoped_css).to end_with("\n}")
      end

      it "allows child class to override parent strategy" do
        # Create a base class with nesting strategy
        base_class = Class.new do
          include StyleCapsule::Component

          css_scoping_strategy :nesting
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
        child = child_class.new
        scoped_css = child.send(:scope_css, child.component_styles)
        expect(scoped_css).to include('[data-capsule="')
        expect(scoped_css).to include('"] .test')
        expect(scoped_css).not_to include('"] {')
      end
    end
  end

  describe "head rendering" do
    it "renders styles in body by default" do
      component_class.class_eval do
        def view_template
          render_capsule_styles
          div { "Content" }
        end

        def render_capsule_styles
          # This would normally render a style tag
          # For testing, we'll just check the method is called
        end
      end

      expect(component_class.head_rendering?).to be false
    end

    it "registers for head rendering when enabled" do
      component_class.stylesheet_registry
      expect(component_class.head_rendering?).to be true
    end

    it "supports namespace for head rendering" do
      component_class.stylesheet_registry namespace: :admin
      expect(component_class.stylesheet_namespace).to eq(:admin)
    end

    describe ".style_capsule" do
      it "sets namespace" do
        component_class.style_capsule namespace: :user
        expect(component_class.stylesheet_namespace).to eq(:user)
        expect(component_class.head_rendering?).to be true
      end

      it "sets namespace without enabling head rendering when head_rendering is false" do
        component_class.style_capsule namespace: :user, head_rendering: false
        expect(component_class.stylesheet_namespace).to eq(:user)
        expect(component_class.head_rendering?).to be false
      end

      it "configures cache strategy" do
        component_class.style_capsule cache_strategy: :time, cache_ttl: 3600
        expect(component_class.inline_cache_strategy).to eq(:time)
        expect(component_class.inline_cache_ttl).to eq(3600)
        expect(component_class.head_rendering?).to be true
      end

      it "configures cache proc" do
        cache_proc = ->(css, capsule_id, namespace) { ["key", true, Time.current + 1800] }
        component_class.style_capsule cache_strategy: :proc, cache_proc: cache_proc
        expect(component_class.inline_cache_strategy).to eq(:proc)
        expect(component_class.inline_cache_proc).to eq(cache_proc)
        expect(component_class.head_rendering?).to be true
      end

      it "configures CSS scoping strategy" do
        component_class.style_capsule css_scoping_strategy: :nesting
        expect(component_class.css_scoping_strategy).to eq(:nesting)
        expect(component_class.head_rendering?).to be false
      end

      it "enables head rendering when any option is provided" do
        component_class.style_capsule namespace: :admin
        expect(component_class.head_rendering?).to be true

        fresh_class = Class.new do
          include StyleCapsule::Component
        end
        fresh_class.style_capsule cache_strategy: :time
        expect(fresh_class.head_rendering?).to be true

        another_fresh_class = Class.new do
          include StyleCapsule::Component
        end
        another_fresh_class.style_capsule cache_ttl: 3600
        expect(another_fresh_class.head_rendering?).to be true
      end

      it "does not enable head rendering when only css_scoping_strategy is provided" do
        component_class.style_capsule css_scoping_strategy: :nesting
        expect(component_class.head_rendering?).to be false
      end

      it "allows explicit head_rendering setting" do
        component_class.style_capsule head_rendering: true
        expect(component_class.head_rendering?).to be true

        fresh_class = Class.new do
          include StyleCapsule::Component
        end
        fresh_class.style_capsule head_rendering: false
        expect(fresh_class.head_rendering?).to be false
      end

      it "configures all options together" do
        component_class.style_capsule(
          namespace: :admin,
          cache_strategy: :time,
          cache_ttl: 1.hour,
          css_scoping_strategy: :nesting,
          head_rendering: true
        )
        expect(component_class.stylesheet_namespace).to eq(:admin)
        expect(component_class.inline_cache_strategy).to eq(:time)
        expect(component_class.inline_cache_ttl).to eq(1.hour)
        expect(component_class.css_scoping_strategy).to eq(:nesting)
        expect(component_class.head_rendering?).to be true
      end
    end

    it "accepts string cache_strategy" do
      component_class.stylesheet_registry cache_strategy: "time", cache_ttl: 3600
      expect(component_class.inline_cache_strategy).to eq(:time)
      expect(component_class.inline_cache_ttl).to eq(3600)
    end

    it "accepts ActiveSupport::Duration for cache_ttl" do
      component_class.stylesheet_registry cache_strategy: :time, cache_ttl: 1.hour
      expect(component_class.inline_cache_strategy).to eq(:time)
      expect(component_class.inline_cache_ttl).to eq(1.hour)
      # Verify it works with Time addition
      expires_at = Time.current + component_class.inline_cache_ttl
      expect(expires_at).to be_a(Time)
      expect(expires_at).to be > Time.current
    end

    it "accepts proc as cache_strategy" do
      cache_proc = ->(css, capsule_id, namespace) {
        ["key_#{capsule_id}", css.length > 50, Time.current + 1800]
      }
      component_class.stylesheet_registry cache_strategy: cache_proc
      expect(component_class.inline_cache_strategy).to eq(:proc)
      expect(component_class.inline_cache_proc).to eq(cache_proc)
    end

    it "rejects invalid cache_strategy" do
      expect {
        component_class.stylesheet_registry cache_strategy: :invalid
      }.to raise_error(ArgumentError, /cache_strategy must be/)
    end

    it "rejects invalid cache_strategy string" do
      expect {
        component_class.stylesheet_registry cache_strategy: "invalid"
      }.to raise_error(ArgumentError, /cache_strategy must be/)
    end

    it "handles nil cache_strategy" do
      component_class.stylesheet_registry cache_strategy: nil
      expect(component_class.inline_cache_strategy).to eq(:none)
    end

    it "rejects invalid cache_strategy type" do
      expect {
        component_class.stylesheet_registry cache_strategy: 123
      }.to raise_error(ArgumentError, /cache_strategy must be a Symbol, String, or Proc/)
    end

    describe ".stylesheet_link_options" do
      it "sets stylesheet link options" do
        options = {"data-turbo-track": "reload"}
        component_class.stylesheet_link_options(options)
        expect(component_class.stylesheet_link_options).to eq(options)
      end

      it "returns nil when options are not set" do
        fresh_class = Class.new do
          include StyleCapsule::Component
        end
        expect(fresh_class.stylesheet_link_options).to be_nil
      end
    end

    describe ".css_scoping_strategy" do
      it "inherits strategy from parent class" do
        parent_class = Class.new do
          include StyleCapsule::Component
        end
        parent_class.css_scoping_strategy(:nesting)

        child_class = Class.new(parent_class) do
          include StyleCapsule::Component
        end

        expect(child_class.css_scoping_strategy).to eq(:nesting)
      end

      it "defaults to selector_patching when no strategy set" do
        fresh_class = Class.new do
          include StyleCapsule::Component
        end
        expect(fresh_class.css_scoping_strategy).to eq(:selector_patching)
      end
    end

    it "registers inline CSS for head rendering when enabled" do
      component_class.stylesheet_registry
      StyleCapsule::StylesheetRegistry.clear

      instance = component_class.new
      instance.send(:render_capsule_styles)

      expect(StyleCapsule::StylesheetRegistry.any?).to be true
    end

    it "renders style tag in body when head rendering is disabled" do
      StyleCapsule::StylesheetRegistry.clear
      StyleCapsule::StylesheetRegistry.clear_manifest
      StyleCapsule::StylesheetRegistry.clear_inline_cache
      instance = component_class.new

      # Mock the style method to capture output
      output = []
      allow(instance).to receive(:style) do |&block|
        output << block.call
      end

      instance.send(:render_capsule_styles)

      expect(output).not_to be_empty
      expect(StyleCapsule::StylesheetRegistry.any?).to be false
    end
  end

  describe "class methods" do
    describe ".capsule_id" do
      it "sets custom scope ID" do
        component_class.capsule_id("custom-123")
        expect(component_class.custom_capsule_id).to eq("custom-123")
        expect(component.component_capsule).to eq("custom-123")
      end

      it "returns nil when capsule_id is not set" do
        # Create a fresh class without setting capsule_id
        fresh_class = Class.new do
          include StyleCapsule::Component
        end
        expect(fresh_class.capsule_id).to be_nil
      end
    end

    describe ".css_cache" do
      it "returns a hash" do
        expect(component_class.css_cache).to be_a(Hash)
      end

      it "caches CSS per component class" do
        other_class = Class.new do
          include StyleCapsule::Component

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
        include StyleCapsule::Component
      end.new
      expect(component_without_styles.send(:component_styles?)).to be false
    end

    it "returns false when component_styles is blank" do
      component_with_blank_styles = Class.new do
        include StyleCapsule::Component

        def component_styles
          ""
        end
      end.new
      expect(component_with_blank_styles.send(:component_styles?)).to be false
    end
  end

  describe "#view_template wrapper" do
    it "wraps content in scoped div when styles are present" do
      output = component.view_template
      # Phlex uses underscores for HTML attributes (data_scope becomes data-capsule in actual HTML)
      expect(output).to include("data_capsule=")
      expect(output).to include("Hello")
    end

    it "renders normally when no styles are present" do
      component_without_styles = Class.new do
        include StyleCapsule::Component

        def view_template
          div { "No styles" }
        end

        def div(options = {}, &block)
          "<div>#{block.call if block_given?}</div>"
        end
      end.new

      output = component_without_styles.view_template
      expect(output).to include("No styles")
      expect(output).not_to include("data-capsule=")
    end
  end

  describe "class method component_styles" do
    let(:component_class_with_class_styles) do
      Class.new do
        include StyleCapsule::Component

        def self.component_styles
          <<~CSS
            .static { color: blue; }
          CSS
        end

        def view_template
          div(class: "static") { "Static" }
        end

        def div(options = {}, &block)
          "<div#{format_options(options)}>#{block.call if block_given?}</div>"
        end

        def style(&block)
          "<style>#{block.call if block_given?}</style>"
        end

        def raw(content)
          content
        end
      end
    end

    it "uses class method component_styles when defined" do
      component = component_class_with_class_styles.new
      expect(component.send(:component_styles?)).to be true
      expect(component.send(:component_styles_content)).to include(".static")
      expect(component.send(:class_styles_only?)).to be true
    end

    it "prefers instance method over class method" do
      component_class_both = Class.new do
        include StyleCapsule::Component

        def self.component_styles
          ".class-method { color: red; }"
        end

        def component_styles
          ".instance-method { color: green; }"
        end

        def view_template
          div { "Both" }
        end

        def div(options = {}, &block)
          "<div>#{block.call if block_given?}</div>"
        end

        def style(&block)
          "<style>#{block.call if block_given?}</style>"
        end

        def raw(content)
          content
        end
      end

      component = component_class_both.new
      expect(component.send(:component_styles_content)).to include(".instance-method")
      expect(component.send(:component_styles_content)).not_to include(".class-method")
      expect(component.send(:class_styles_only?)).to be false
    end

    it "handles NoMethodError when class method raises error" do
      component_class_error = Class.new do
        include StyleCapsule::Component

        def self.respond_to?(method, include_private = false)
          return true if method == :component_styles
          super
        end

        def self.component_styles
          raise NoMethodError, "Method not available"
        end

        def view_template
          div { "Error" }
        end

        def div(options = {}, &block)
          "<div>#{block.call if block_given?}</div>"
        end
      end

      component = component_class_error.new
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
        component_class_file = Class.new do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            ".file-cached { color: orange; }"
          end

          def view_template
            div(class: "file-cached") { "File Cached" }
          end

          def div(options = {}, &block)
            "<div>#{block.call if block_given?}</div>"
          end
        end

        component = component_class_file.new
        expect(component.send(:file_caching_allowed?)).to be true
        component.send(:render_capsule_styles)

        # Should write file
        expect(StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class_file,
          capsule_id: component.component_capsule
        )).to be true
      end

      it "falls back to :none when file caching requested but instance method used" do
        component_class_instance = Class.new do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def component_styles
            ".instance { color: purple; }"
          end

          def view_template
            div { "Instance" }
          end

          def div(options = {}, &block)
            "<div>#{block.call if block_given?}</div>"
          end
        end

        component = component_class_instance.new
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
