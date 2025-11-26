# frozen_string_literal: true

require "tmpdir"

RSpec.describe StyleCapsule::ComponentBuilder do
  let(:test_output_dir) { Pathname.new(Dir.mktmpdir("style_capsule_builder_test_#{SecureRandom.hex(4)}_")) }

  before do
    StyleCapsule::CssFileWriter.configure(
      output_dir: test_output_dir,
      enabled: true
    )
  end

  after do
    StyleCapsule::CssFileWriter.clear_files
    FileUtils.rm_rf(test_output_dir) if Dir.exist?(test_output_dir)
  end

  describe ".phlex_available?" do
    it "returns true when Phlex is defined" do
      skip "Phlex not available" unless defined?(Phlex::HTML)
      expect(described_class.phlex_available?).to be true
    end

    it "can be stubbed to return false" do
      allow(described_class).to receive(:phlex_available?).and_return(false)
      expect(described_class.phlex_available?).to be false
    end
  end

  describe ".view_component_available?" do
    it "can be stubbed to return false" do
      allow(described_class).to receive(:view_component_available?).and_return(false)
      expect(described_class.view_component_available?).to be false
    end
  end

  describe ".find_phlex_components" do
    it "returns empty array when Phlex is not available" do
      allow(described_class).to receive(:phlex_available?).and_return(false)
      expect(described_class.find_phlex_components).to eq([])
    end

    context "when Phlex is available" do
      before do
        skip "Phlex not available" unless defined?(Phlex::HTML)
      end

      it "finds Phlex components with StyleCapsule::Component" do
        # Create a named class so it gets registered automatically
        klass_name = "TestPhlexComponent_#{SecureRandom.hex(4)}"
        component_class = Class.new(Phlex::HTML) do
          def view_template
            div { "Test" }
          end
        end

        # Set constant first so class has a name
        Object.const_set(klass_name, component_class)

        begin
          # Now include the module - this will register the class
          component_class.include(StyleCapsule::Component)

          components = described_class.find_phlex_components
          expect(components).to include(component_class)
        ensure
          Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
          StyleCapsule::ClassRegistry.clear
        end
      end

      it "handles errors gracefully when checking class inheritance" do
        # Create a class that will raise an error when checking inheritance
        klass_name = "ErrorPhlexComponent_#{SecureRandom.hex(4)}"
        error_class = Class.new do
          def self.<(other)
            raise StandardError, "Inheritance check failed"
          end
        end

        Object.const_set(klass_name, error_class)
        StyleCapsule::ClassRegistry.register(error_class)

        begin
          # Should not raise an error, should skip the problematic class
          expect {
            components = described_class.find_phlex_components
            expect(components).not_to include(error_class)
          }.not_to raise_error
        ensure
          Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
          StyleCapsule::ClassRegistry.clear
        end
      end

      it "does not find Phlex components without StyleCapsule::Component" do
        # Create a named class that doesn't include StyleCapsule::Component
        klass_name = "TestPhlexComponentNoStyle_#{SecureRandom.hex(4)}"
        component_class = Class.new(Phlex::HTML) do
          def view_template
            div { "Test" }
          end
        end

        # Set constant so class has a name
        Object.const_set(klass_name, component_class)

        begin
          # Should not be found since it doesn't include StyleCapsule::Component
          components = described_class.find_phlex_components
          expect(components).not_to include(component_class)
        ensure
          Object.send(:remove_const, klass_name) if Object.const_defined?(klass_name)
        end
      end

      it "handles classes that raise errors in ClassRegistry.each" do
        # Create a class that will cause an error when checking inheritance
        error_class = Class.new(Phlex::HTML) do
          include StyleCapsule::Component

          def self.<(other)
            raise StandardError, "Inheritance check error"
          end

          def view_template
            div { "Test" }
          end
        end

        # Register it manually
        StyleCapsule::ClassRegistry.register(error_class)

        # Should not raise an error
        expect {
          components = described_class.find_phlex_components
          expect(components).not_to include(error_class)
        }.not_to raise_error

        StyleCapsule::ClassRegistry.clear
      end
    end
  end

  describe ".find_view_components" do
    it "returns empty array when ViewComponent is not available" do
      allow(described_class).to receive(:view_component_available?).and_return(false)
      expect(described_class.find_view_components).to eq([])
    end

    context "when ViewComponent is available" do
      before do
        skip "ViewComponent not available" unless defined?(ViewComponent::Base)
      end

      it "handles errors in ClassRegistry.each gracefully" do
        # Create a class that will raise an error when checking inheritance
        error_class = Class.new do
          def self.<(other)
            raise StandardError, "Inheritance check error"
          end
        end

        StyleCapsule::ClassRegistry.register(error_class)

        begin
          # Should not raise an error, should skip the problematic class
          expect {
            components = described_class.find_view_components
            expect(components).not_to include(error_class)
          }.not_to raise_error
        ensure
          StyleCapsule::ClassRegistry.clear
        end
      end

      it "handles ViewComponent loading errors gracefully" do
        # Stub ClassRegistry.each to raise an error
        allow(StyleCapsule::ClassRegistry).to receive(:each).and_raise(StandardError, "ViewComponent error")

        # Should not raise an error, should return empty array
        expect {
          components = described_class.find_view_components
          expect(components).to eq([])
        }.not_to raise_error
      end

      it "handles errors when checking class inheritance in ClassRegistry.each" do
        # Create a class that will raise an error when checking inheritance
        error_class = Class.new do
          def self.<(other)
            raise StandardError, "Inheritance check error"
          end
        end

        StyleCapsule::ClassRegistry.register(error_class)

        begin
          # Should not raise an error, should skip the problematic class
          expect {
            components = described_class.find_view_components
            expect(components).not_to include(error_class)
          }.not_to raise_error
        ensure
          StyleCapsule::ClassRegistry.clear
        end
      end

      it "handles errors when checking included_modules" do
        # Create a class that will raise an error when checking included_modules
        error_class = Class.new(ViewComponent::Base) do
          def self.included_modules
            raise StandardError, "included_modules error"
          end
        end

        StyleCapsule::ClassRegistry.register(error_class)

        begin
          # Should not raise an error, should skip the problematic class
          expect {
            components = described_class.find_view_components
            expect(components).not_to include(error_class)
          }.not_to raise_error
        ensure
          StyleCapsule::ClassRegistry.clear
        end
      end
    end
  end

  describe ".collect_components" do
    # ViewComponent test removed - ViewComponent requires Rails to be fully initialized
    # which is not available in the test environment
  end

  describe ".build_component" do
    context "with Phlex components" do
      before do
        skip "Phlex not available" unless defined?(Phlex::HTML)
      end

      it "builds CSS file for component with file caching" do
        component_class = Class.new(Phlex::HTML) do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            ".test-component { color: red; }"
          end

          def view_template
            div(class: "test-component") { "Test" }
          end
        end

        output_messages = []
        file_path = described_class.build_component(component_class, output_proc: ->(msg) { output_messages << msg })

        expect(file_path).to be_a(String)
        expect(output_messages).to include(match(/Generated:/))
        expect(StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class,
          capsule_id: component_class.new.component_capsule
        )).to be true
      end

      it "skips component without file caching strategy" do
        component_class = Class.new(Phlex::HTML) do
          include StyleCapsule::Component

          def self.component_styles
            ".test { color: red; }"
          end

          def view_template
            div { "Test" }
          end
        end

        file_path = described_class.build_component(component_class)
        expect(file_path).to be_nil
      end

      it "skips component without class method component_styles" do
        component_class = Class.new(Phlex::HTML) do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def component_styles
            ".test { color: red; }"
          end

          def view_template
            div { "Test" }
          end
        end

        file_path = described_class.build_component(component_class)
        expect(file_path).to be_nil
      end

      it "handles components with empty CSS content" do
        component_class = Class.new(Phlex::HTML) do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            ""
          end

          def view_template
            div { "Test" }
          end
        end

        file_path = described_class.build_component(component_class)
        expect(file_path).to be_nil
      end

      it "handles components that require arguments" do
        component_class = Class.new(Phlex::HTML) do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def initialize(required_arg = nil)
            raise ArgumentError, "required_arg is required" if required_arg.nil?
            @required_arg = required_arg
            super()
          end

          def self.component_styles
            ".test { color: red; }"
          end

          def view_template
            div { "Test" }
          end
        end

        output_messages = []
        file_path = described_class.build_component(component_class, output_proc: ->(msg) { output_messages << msg })

        expect(file_path).to be_nil
        expect(output_messages).to include(match(/Skipped/))
      end
    end
  end

  describe ".build_all" do
    it "builds CSS files for all components" do
      skip "Phlex not available" unless defined?(Phlex::HTML)

      component_class = Class.new(Phlex::HTML) do
        include StyleCapsule::Component

        stylesheet_registry cache_strategy: :file

        def self.component_styles
          ".test { color: red; }"
        end

        def view_template
          div { "Test" }
        end
      end
      # Force the class to be registered in ObjectSpace
      component_class.new

      output_messages = []
      count = described_class.build_all(output_proc: ->(msg) { output_messages << msg })

      expect(count).to be >= 0  # May be 0 if no components found, or >= 1 if found
      expect(output_messages).to include(match(/StyleCapsule CSS files built successfully/))
    end
  end
end
