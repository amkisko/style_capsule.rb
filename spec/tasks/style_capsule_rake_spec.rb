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

    component_class = Class.new(Phlex::HTML, &block)
    const_name = "RakeTest#{name}_#{component_class.object_id}"
    Object.const_set(const_name, component_class) unless component_class.name
    @created_components << component_class
    component_class
  end

  def create_view_component(name, &block)
    skip "ViewComponent not available" unless defined?(ViewComponent::Base)

    component_class = Class.new(ViewComponent::Base, &block)
    const_name = "RakeTest#{name}_#{component_class.object_id}"
    Object.const_set(const_name, component_class) unless component_class.name
    @created_components << component_class
    component_class
  end

  describe "style_capsule:build" do
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

        # Force the class to be registered in ObjectSpace by creating an instance
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

        # Force the class to be registered in ObjectSpace by creating an instance
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

        # Force the class to be registered in ObjectSpace
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
        output.string
        # The component might not be found by ObjectSpace if it can't be instantiated
        # So we just verify the task completes without error
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

    context "with ViewComponent components" do
      before do
        skip "ViewComponent not available" unless defined?(ViewComponent::Base)
      end

      it "finds ViewComponent components with file caching" do
        component_class = create_view_component("ViewComponentFileCache") do
          include StyleCapsule::ViewComponent

          stylesheet_registry cache_strategy: :file

          def self.component_styles
            ".view-component { color: green; }"
          end

          def call
            content_tag(:div, "Test", class: "view-component")
          end

          # ViewComponent::Base might require view_context, so provide a minimal one
          def initialize(view_context: nil, **kwargs)
            super(**kwargs)
          end
        end

        # Force the class to be registered in ObjectSpace
        # ViewComponent might need view_context, but for rake task we just need the class
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
        expect(css_content).to include(".view-component")
      end
    end
  end

  describe "style_capsule:clear" do
    it "removes generated CSS files" do
      # Create a test file
      test_file = test_output_dir.join("test-component-abc123.css")
      FileUtils.mkdir_p(test_output_dir)
      File.write(test_file, ".test { color: red; }")

      expect(File.exist?(test_file)).to be true

      # Invoke clear task (reenable in case it was cleared)
      Rake::Task["style_capsule:clear"].reenable
      Rake::Task["style_capsule:clear"].invoke

      # Verify file was removed
      expect(File.exist?(test_file)).to be false
    end

    it "handles empty directory gracefully" do
      # Ensure directory exists but is empty
      FileUtils.mkdir_p(test_output_dir)

      # Should not raise an error
      Rake::Task["style_capsule:clear"].reenable
      expect { Rake::Task["style_capsule:clear"].invoke }.not_to raise_error
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
  end
end
