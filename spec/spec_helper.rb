require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter { |source_file| source_file.lines.count < 5 }
end

require "simplecov-cobertura"
SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter

require "rspec"
require "rspec/mocks"
require "active_support/all"
require "ostruct"

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
        @config ||= OpenStruct.new(assets: OpenStruct.new(paths: []))
      end

      def self.config=(value)
        @config = value
      end

      def routes
        @routes ||= ::OpenStruct.new(url_helpers: Module.new)
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
          @config ||= OpenStruct.new
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

RSpec.configure do |config|
  # Include RSpec mocks for all tests
  config.include RSpec::Mocks::ExampleMethods

  # Define integration test type
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  # Setup for integration tests
  config.before(:each, type: :integration) do
    # Reset CurrentAttributes context
    StyleCapsule::StylesheetRegistry.reset
    # Clear registries before each integration test
    StyleCapsule::StylesheetRegistry.clear
    StyleCapsule::StylesheetRegistry.clear_manifest
    StyleCapsule::StylesheetRegistry.clear_inline_cache
  end

  # Reset CurrentAttributes after each test (if available)
  config.after(:each) do
    # Only call reset if we're actually using CurrentAttributes
    # Check both respond_to? and that it's actually a CurrentAttributes method
    if StyleCapsule::StylesheetRegistry.respond_to?(:reset) &&
        StyleCapsule::StylesheetRegistry.using_current_attributes?
      StyleCapsule::StylesheetRegistry.reset
    end
  end
end
