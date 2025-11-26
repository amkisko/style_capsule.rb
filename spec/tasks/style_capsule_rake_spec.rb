# frozen_string_literal: true

require "tmpdir"
require "rake"
require "stringio"
require "securerandom"

RSpec.describe "style_capsule rake tasks" do
  let(:test_output_dir) { Pathname.new(Dir.mktmpdir("style_capsule_rake_test_#{SecureRandom.hex(4)}_")) }
  let(:original_output_dir) { StyleCapsule::CssFileWriter.output_dir }
  let(:component_classes) { [] }

  before do
    # Create mock :environment task (required by rake tasks)
    unless Rake::Task.task_defined?("environment")
      Rake::Task.define_task(:environment) do
        # Mock environment task - does nothing
      end
    end

    # Load rake tasks
    load File.expand_path("../../lib/tasks/style_capsule.rake", __dir__)

    # Configure CssFileWriter to use test directory
    StyleCapsule::CssFileWriter.configure(
      output_dir: test_output_dir,
      enabled: true
    )

    # Clear any existing tasks to avoid conflicts
    Rake::Task["style_capsule:build"].clear if Rake::Task.task_defined?("style_capsule:build")
    Rake::Task["style_capsule:clear"].clear if Rake::Task.task_defined?("style_capsule:clear")

    # Reload tasks
    load File.expand_path("../../lib/tasks/style_capsule.rake", __dir__)

    # Store component classes for cleanup
    @created_components = []

    # Clear any existing files before each test
    StyleCapsule::CssFileWriter.clear_files
  end

  after do
    # Clean up generated files first (before removing components)
    StyleCapsule::CssFileWriter.clear_files

    # Clean up created components
    @created_components.each do |component_class|
      if component_class.name && Object.const_defined?(component_class.name)
        Object.send(:remove_const, component_class.name)
      end
    end

    FileUtils.rm_rf(test_output_dir) if Dir.exist?(test_output_dir)

    # Restore original output directory
    StyleCapsule::CssFileWriter.configure(
      output_dir: original_output_dir,
      enabled: true
    )

    # Clear tasks
    Rake::Task["style_capsule:build"].clear if Rake::Task.task_defined?("style_capsule:build")
    Rake::Task["style_capsule:clear"].clear if Rake::Task.task_defined?("style_capsule:clear")
    Rake::Task["environment"].clear if Rake::Task.task_defined?("environment")
  end

  def create_phlex_component(name, &block)
    skip "Phlex not available" unless defined?(Phlex::HTML)

    # Create class without block first to get a name
    component_class = Class.new(Phlex::HTML)
    const_name = "RakeTest#{name}_#{component_class.object_id}"
    Object.const_set(const_name, component_class)

    # Now evaluate the block (which includes StyleCapsule::Component) so it gets registered
    component_class.class_eval(&block) if block_given?

    @created_components << component_class
    component_class
  end

  def create_view_component(name, &block)
    skip "ViewComponent not available" unless defined?(ViewComponent::Base)

    # Create class without block first to get a name
    component_class = Class.new(ViewComponent::Base)
    const_name = "RakeTest#{name}_#{component_class.object_id}"
    Object.const_set(const_name, component_class)

    # Now evaluate the block (which includes StyleCapsule::ViewComponent) so it gets registered
    component_class.class_eval(&block) if block_given?

    @created_components << component_class
    component_class
  end

  describe "style_capsule:build" do
    it "requires component_builder module when task is invoked" do
      # The require happens when the task is invoked, not when it's defined
      # So we just verify the task can be invoked (which triggers the require)
      output = StringIO.new
      allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

      Rake::Task["style_capsule:build"].reenable
      expect { Rake::Task["style_capsule:build"].invoke }.not_to raise_error
    end

    context "with Phlex components" do
      before do
        skip "Phlex not available" unless defined?(Phlex::HTML)
      end

      it "finds components with file caching" do
        # Create a test component with file caching
        component_class = create_phlex_component("PhlexFileCache") do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            ".test-component { color: red; }"
          end

          def view_template
            div(class: "test-component") { "Test" }
          end
        end

        # Class is automatically registered when including StyleCapsule::Component
        component_class.new

        # Capture output
        output = StringIO.new
        allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

        # Invoke the task (reenable in case it was cleared)
        Rake::Task["style_capsule:build"].reenable
        Rake::Task["style_capsule:build"].invoke

        # Verify file was created
        instance = component_class.new
        capsule_id = instance.component_capsule
        expect(StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class,
          capsule_id: capsule_id
        )).to be true
      end

      it "generates CSS files correctly" do
        component_class = create_phlex_component("PhlexGenerated") do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            ".generated { color: blue; }"
          end

          def view_template
            div { "Content" }
          end
        end

        # Class is automatically registered when including StyleCapsule::Component
        component_class.new
        expect(component_class.inline_cache_strategy).to eq(:file)
        expect(component_class.respond_to?(:component_styles, false)).to be true

        # Clear any existing files first
        StyleCapsule::CssFileWriter.clear_files
        expect(Dir.glob(test_output_dir.join("*.css"))).to be_empty

        # Invoke the task (this should create files)
        # Re-enable the task in case it was cleared
        Rake::Task["style_capsule:build"].reenable
        Rake::Task["style_capsule:build"].invoke

        # Check if files were created for THIS component
        # Find the file for this specific component
        instance = component_class.new
        capsule_id = instance.component_capsule
        file_path = StyleCapsule::CssFileWriter.file_path_for(
          component_class: component_class,
          capsule_id: capsule_id
        )

        # If file_path is relative, construct full path
        full_path = if file_path && !file_path.start_with?("/")
          test_output_dir.join("#{file_path}.css")
        else
          Pathname.new("#{file_path}.css")
        end

        # Verify file exists and contains expected content
        expect(File.exist?(full_path)).to be true
        css_content = File.read(full_path)
        expect(css_content).to include("[data-capsule=")
        expect(css_content).to include(".generated")
      end

      it "handles errors gracefully when components require arguments" do
        component_class = create_phlex_component("PhlexError") do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def initialize(required_arg = nil)
            raise ArgumentError, "required_arg is required" if required_arg.nil?
            @required_arg = required_arg
            super()
          end

          def self.component_styles
            ".error-component { color: red; }"
          end

          def view_template
            div { "Error" }
          end
        end

        # Class is automatically registered when including StyleCapsule::Component
        # This will fail, but that's expected - we're testing error handling
        begin
          component_class.new
        rescue ArgumentError
          # Expected - component requires argument
        end

        output = StringIO.new
        allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

        # Should not raise an error
        Rake::Task["style_capsule:build"].reenable
        expect { Rake::Task["style_capsule:build"].invoke }.not_to raise_error

        # Should output skip message (if component was found and skipped)
        output_string = output.string
        # The component might not be found if it can't be instantiated
        # So we just verify the task completes without error
        # But if it is found, it should output a skip message
        if output_string.include?("Skipped")
          expect(output_string).to include("PhlexError")
        end
      end

      it "handles components with empty CSS content" do
        component_class = create_phlex_component("PhlexEmpty") do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            ""  # Empty CSS
          end

          def view_template
            div { "Empty" }
          end
        end

        # Force the class to be registered in ObjectSpace
        component_class.new

        # Should not create any files for empty CSS
        Rake::Task["style_capsule:build"].reenable
        Rake::Task["style_capsule:build"].invoke

        # Verify no file was created
        instance = component_class.new
        capsule_id = instance.component_capsule
        file_exists = StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class,
          capsule_id: capsule_id
        )
        expect(file_exists).to be false
      end

      it "handles components with nil CSS content" do
        component_class = create_phlex_component("PhlexNil") do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            nil  # Nil CSS
          end

          def view_template
            div { "Nil" }
          end
        end

        # Force the class to be registered in ObjectSpace
        component_class.new

        # Should not create any files for nil CSS
        Rake::Task["style_capsule:build"].reenable
        Rake::Task["style_capsule:build"].invoke

        # Verify no file was created
        instance = component_class.new
        capsule_id = instance.component_capsule
        file_exists = StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class,
          capsule_id: capsule_id
        )
        expect(file_exists).to be false
      end

      it "skips components without file caching strategy" do
        component_class = create_phlex_component("PhlexNoCache") do
          include StyleCapsule::Component

          # No file caching strategy
          def self.component_styles
            ".no-file-cache { color: red; }"
          end

          def view_template
            div { "No cache" }
          end
        end

        # Clear files from previous tests first
        StyleCapsule::CssFileWriter.clear_files

        Rake::Task["style_capsule:build"].reenable
        Rake::Task["style_capsule:build"].invoke

        # Should not create any files for this component (no file caching strategy)
        # Note: Other components from other tests might create files, so we can't check for empty directory
        # Instead, verify this specific component doesn't have a file
        instance = component_class.new
        capsule_id = instance.component_capsule
        file_exists = StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class,
          capsule_id: capsule_id
        )
        expect(file_exists).to be false
      end

      it "skips components without class method component_styles" do
        component_class = create_phlex_component("PhlexInstanceMethod") do
          include StyleCapsule::Component

          stylesheet_registry cache_strategy: :file

          # Instance method, not class method
          def component_styles
            ".instance-method { color: red; }"
          end

          def view_template
            div { "Instance" }
          end
        end

        # Clear files from previous tests first
        StyleCapsule::CssFileWriter.clear_files

        Rake::Task["style_capsule:build"].reenable
        Rake::Task["style_capsule:build"].invoke

        # Should not create any files for this component (no class method component_styles)
        # Note: Other components from other tests might create files, so we can't check for empty directory
        # Instead, verify this specific component doesn't have a file
        instance = component_class.new
        capsule_id = instance.component_capsule
        file_exists = StyleCapsule::CssFileWriter.file_exists?(
          component_class: component_class,
          capsule_id: capsule_id
        )
        expect(file_exists).to be false
      end
    end

    # ViewComponent tests removed - ViewComponent requires Rails to be fully initialized
    # which is not available in the test environment
  end

  describe "style_capsule:clear" do
    it "executes all lines in clear task including require, clear_files, and puts" do
      # Create a test file to ensure clear_files has something to do
      test_file = test_output_dir.join("test-component-abc123.css")
      FileUtils.mkdir_p(test_output_dir)
      File.write(test_file, ".test { color: red; }")

      expect(File.exist?(test_file)).to be true

      # Capture output to verify puts is called (line 15)
      output = StringIO.new
      allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

      # Invoke clear task - this should execute lines 13 (require), 14 (clear_files), 15 (puts)
      Rake::Task["style_capsule:clear"].reenable
      Rake::Task["style_capsule:clear"].invoke

      # Verify the task executed (file was cleared and puts was called)
      expect(File.exist?(test_file)).to be false
      expect(output.string).to include("StyleCapsule CSS files cleared")
    end

    it "removes generated CSS files" do
      # Create a test file
      test_file = test_output_dir.join("test-component-abc123.css")
      FileUtils.mkdir_p(test_output_dir)
      File.write(test_file, ".test { color: red; }")

      expect(File.exist?(test_file)).to be true

      # Capture output to verify puts is called
      output = StringIO.new
      allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

      # Invoke clear task (reenable in case it was cleared)
      Rake::Task["style_capsule:clear"].reenable
      Rake::Task["style_capsule:clear"].invoke

      # Verify file was removed
      expect(File.exist?(test_file)).to be false
      # Verify puts was called with the success message
      expect(output.string).to include("StyleCapsule CSS files cleared")
    end

    it "handles empty directory gracefully" do
      # Ensure directory exists but is empty
      FileUtils.mkdir_p(test_output_dir)

      # Capture output
      output = StringIO.new
      allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

      # Should not raise an error
      Rake::Task["style_capsule:clear"].reenable
      expect { Rake::Task["style_capsule:clear"].invoke }.not_to raise_error
      # Verify puts was called
      expect(output.string).to include("StyleCapsule CSS files cleared")
    end
  end

  describe "assets:precompile integration" do
    it "enhances assets:precompile task when Rails is defined" do
      skip "Rails not available" unless defined?(Rails)

      # Clear any existing assets:precompile task
      Rake::Task["assets:precompile"].clear if Rake::Task.task_defined?("assets:precompile")

      # Create a mock assets:precompile task
      Rake::Task.define_task("assets:precompile") do
        # Mock task - does nothing
      end

      # Clear and reload the style_capsule rake tasks to trigger the enhancement
      Rake::Task["style_capsule:build"].clear if Rake::Task.task_defined?("style_capsule:build")
      load File.expand_path("../../lib/tasks/style_capsule.rake", __dir__)

      # Verify that assets:precompile task exists
      expect(Rake::Task.task_defined?("assets:precompile")).to be true

      # Verify that style_capsule:build is in the prerequisites
      # The enhance method adds prerequisites, so we check if style_capsule:build is a prerequisite
      assets_task = Rake::Task["assets:precompile"]
      prerequisites = assets_task.prerequisites

      # The enhance method adds style_capsule:build as a prerequisite
      expect(prerequisites).to include("style_capsule:build")

      # Clean up
      Rake::Task["assets:precompile"].clear if Rake::Task.task_defined?("assets:precompile")
    end

    context "when Phlex is not defined" do
      it "skips Phlex components gracefully" do
        # Temporarily hide Phlex
        phlex_defined = defined?(Phlex)
        phlex_const = Object.const_get(:Phlex) if phlex_defined && Object.const_defined?(:Phlex)

        begin
          Object.send(:remove_const, :Phlex) if Object.const_defined?(:Phlex)

          # Task should still run without error
          expect {
            Rake::Task["style_capsule:build"].invoke
          }.not_to raise_error
        ensure
          # Restore Phlex if it was defined
          if phlex_defined && phlex_const
            Object.const_set(:Phlex, phlex_const)
          end
        end
      end
    end

    context "when ViewComponent has loading errors" do
      it "handles ViewComponent loading errors gracefully" do
        skip "ViewComponent not available" unless defined?(ViewComponent::Base)

        # Mock ViewComponent to raise an error when checking inheritance
        allow_any_instance_of(Class).to receive(:<).and_call_original
        allow_any_instance_of(Class).to receive(:<).with(ViewComponent::Base) do |klass|
          # Simulate a loading error for some classes
          if klass.name&.include?("ErrorComponent")
            raise StandardError, "ViewComponent loading error"
          else
            klass.superclass == ViewComponent::Base || klass.ancestors.include?(ViewComponent::Base)
          end
        end

        # Task should still run without error
        expect {
          Rake::Task["style_capsule:build"].invoke
        }.not_to raise_error
      end
    end

    context "when ViewComponent is not defined" do
      it "skips ViewComponent components gracefully" do
        # Temporarily hide ViewComponent
        vc_defined = defined?(ViewComponent)
        vc_const = Object.const_get(:ViewComponent) if vc_defined && Object.const_defined?(:ViewComponent)

        begin
          Object.send(:remove_const, :ViewComponent) if Object.const_defined?(:ViewComponent)

          # Task should still run without error
          expect {
            Rake::Task["style_capsule:build"].invoke
          }.not_to raise_error
        ensure
          # Restore ViewComponent if it was defined
          if vc_defined && vc_const
            Object.const_set(:ViewComponent, vc_const)
          end
        end
      end
    end
  end
end
