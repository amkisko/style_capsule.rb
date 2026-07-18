polyrun_cov_measure =
  ENV["POLYRUN_COVERAGE_DISABLE"] != "1" &&
  %w[1 true yes].include?(ENV["POLYRUN_COVERAGE"]&.to_s&.downcase)

if polyrun_cov_measure
  require "coverage"
  branch = %w[1 true yes].include?(ENV["POLYRUN_COVERAGE_BRANCHES"]&.to_s&.downcase)
  ::Coverage.start(lines: true, branches: branch)
end

if polyrun_cov_measure
  require "polyrun/coverage/rails"
  Polyrun::Coverage::Rails.start!(root: File.expand_path("..", __dir__))
end

require "rspec"
require "rspec/mocks"
require "active_support/all"
require "tmpdir"
require "fileutils"

module StyleCapsule
  # Lightweight Rails test doubles (avoid ostruct stdlib deprecation on Ruby 3.5+)
  module SpecRailsMocks
    AssetsConfig = Struct.new(:paths)

    RoutesConfig = Struct.new(:url_helpers)
    ApplicationConfig = Struct.new(:assets)
  end
end

# Mock Rails constant if it doesn't exist (needed for railties and ViewComponent)
unless defined?(Rails)
  module Rails
    def self.env
      @env ||= ActiveSupport::StringInquirer.new("test")
    end

    def self.root
      @root ||= Pathname.new(Dir.pwd)
    end

    def self.version
      @version ||= Gem::Version.new("7.0.0")
    end

    # VERSION module for gems that expect Rails::VERSION::MAJOR, etc.
    # ViewComponent 4.x accesses Rails::VERSION::MAJOR and Rails::VERSION::MINOR
    # Also acts as a string for compatibility
    module VERSION
      MAJOR = 7
      MINOR = 0
      PATCH = 0
      STRING = "7.0.0"

      def self.to_s
        STRING
      end

      def self.inspect
        STRING.inspect
      end
    end

    class Application
      def self.env
        Rails.env
      end

      def self.config
        @config ||= StyleCapsule::SpecRailsMocks::ApplicationConfig.new(
          assets: StyleCapsule::SpecRailsMocks::AssetsConfig.new(paths: [])
        )
      end

      def self.config=(value)
        @config = value
      end

      def routes
        @routes ||= StyleCapsule::SpecRailsMocks::RoutesConfig.new(url_helpers: Module.new)
      end
    end

    def self.application
      @application ||= Application.new
    end
  end
end

# Load railties for testing (even if Rails constant isn't defined)
begin
  require "railties"
  # Mock Rails::Railtie if it doesn't exist
  unless defined?(Rails::Railtie)
    module Rails
      class Railtie
        def self.config
          @config ||= ActiveSupport::OrderedOptions.new
        end

        def self.config=(value)
          @config = value
        end
      end
    end
  end
  # Initialize CurrentAttributes by requiring the library
  # This ensures CurrentAttributes works properly
  require_relative "../lib/style_capsule/stylesheet_registry"
  require_relative "../lib/style_capsule/railtie"
rescue LoadError
  # Railties not available, skip railtie tests
end

# Load Phlex for integration tests (optional)
begin
  require "phlex"
rescue LoadError
  # Phlex not available, integration tests will be skipped
end

# Load ViewComponent for integration tests (optional)
# Note: ViewComponent 4.x requires Rails to be initialized
# ViewComponent 4.x may have issues loading in test environments without full Rails setup
# Tests will skip if ViewComponent cannot be loaded properly
begin
  require "view_component"
rescue LoadError, NameError, TypeError
  # ViewComponent not available or Rails not properly initialized, integration tests will be skipped
  # ViewComponent 4.x may fail to load if Rails is not fully initialized
  # This is expected in minimal test environments - tests will skip gracefully
end

# Mock ActionView::Base for integration tests
unless defined?(ActionView::Base)
  module ActionView
    class Base
      def initialize
        @output_buffer = ActiveSupport::SafeBuffer.new
      end

      def content_tag(tag, content = nil, options = {}, &block)
        content = block.call if block_given?
        attrs = options.map { |k, v| %(#{k}="#{v}") }.join(" ")
        attrs = " #{attrs}" unless attrs.empty?
        "<#{tag}#{attrs}>#{content}</#{tag}>".html_safe
      end

      def stylesheet_link_tag(path, **options)
        attrs = options.map { |k, v| %(#{k}="#{v}") }.join(" ")
        attrs = " #{attrs}" unless attrs.empty?
        %(<link rel="stylesheet" href="/assets/#{path}.css"#{attrs}>).html_safe
      end
    end
  end
end

require_relative "../lib/style_capsule"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require_relative f }

# Configure CssFileWriter to use a temporary directory for all tests
# This prevents tests from creating directories in the project root
RSpec.configure do |config|
  config.before(:suite) do
    # Use a temporary directory for CSS file writing during tests
    test_output_dir = Pathname.new(Dir.mktmpdir("style_capsule_spec_"))
    StyleCapsule::CssFileWriter.configure(
      output_dir: test_output_dir,
      enabled: true
    )
  end

  config.after(:suite) do
    # Clean up test output directory
    output_dir = StyleCapsule::CssFileWriter.output_dir
    if output_dir && Dir.exist?(output_dir) && output_dir.to_s.include?("style_capsule_spec_")
      StyleCapsule::CssFileWriter.clear_files
      FileUtils.rm_rf(output_dir)
    end
  end
end

RSpec.configure do |config|
  # Include RSpec mocks for all tests
  config.include RSpec::Mocks::ExampleMethods

  # Define integration test type
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  # Setup for integration tests
  config.before(:each, type: :integration) do
    # Reset CurrentAttributes context (if available)
    if StyleCapsule::StylesheetRegistry.respond_to?(:reset) &&
        StyleCapsule::StylesheetRegistry.using_current_attributes?
      StyleCapsule::StylesheetRegistry.reset
    end
    # Clear registries before each integration test
    StyleCapsule::StylesheetRegistry.clear
    StyleCapsule::StylesheetRegistry.clear_manifest
    StyleCapsule::StylesheetRegistry.clear_inline_cache
  end

  # Reset CurrentAttributes after each test (if available)
  config.after do
    # Only call reset if we're actually using CurrentAttributes
    # Check both respond_to? and that it's actually a CurrentAttributes method
    if StyleCapsule::StylesheetRegistry.respond_to?(:reset) &&
        StyleCapsule::StylesheetRegistry.using_current_attributes?
      StyleCapsule::StylesheetRegistry.reset
    end
  end
end
require "polyrun/rspec"
Polyrun::RSpec.install_sharded_formatter_compat!
Polyrun::RSpec.install_failure_fragments!
Polyrun::RSpec.install_worker_ping!
Polyrun::RSpec.install_example_debug!
Polyrun::RSpec.install_example_rails_logging!
Polyrun::RSpec.install_example_timeout!
if %w[1 true yes].include?(ENV["POLYRUN_SPEC_QUALITY"]&.to_s&.downcase)
  Polyrun::RSpec.install_spec_quality!
end
