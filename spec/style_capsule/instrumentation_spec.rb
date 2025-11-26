# frozen_string_literal: true

RSpec.describe StyleCapsule::Instrumentation do
  describe ".available?" do
    it "returns true when ActiveSupport::Notifications is available" do
      # available? checks defined?(ActiveSupport::Notifications)
      expect(described_class.available?).to be_truthy
    end
  end

  describe ".instrument" do
    let(:component_class) do
      Class.new do
        def self.name
          "TestComponent"
        end
      end
    end

    it "executes block when no subscribers exist" do
      result = described_class.instrument("style_capsule.test.no_subscribers_#{SecureRandom.hex}", {}) do
        "result"
      end
      expect(result).to eq("result")
    end

    it "calculates input_size from css_content in payload" do
      css = ".test { color: red; }"
      payload = {css_content: css}

      # Subscribe to the event to trigger the code path
      subscriber = ActiveSupport::Notifications.subscribe("style_capsule.test.css_content") do |*args|
        # Event handler
      end

      begin
        result = described_class.instrument("style_capsule.test.css_content", payload) do
          "result"
        end

        # The payload is modified in place before passing to ActiveSupport::Notifications
        # But ActiveSupport::Notifications may create a copy, so we check the original
        # Actually, the modification happens before the block, so it should be in the payload
        expect(payload[:input_size]).to eq(css.bytesize)
        expect(result).to eq("result")
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

    it "calculates input_size from input in payload" do
      input = "some input"
      payload = {input: input}

      # Subscribe to the event to trigger the code path
      subscriber = ActiveSupport::Notifications.subscribe("style_capsule.test.input") do |*args|
        # Event handler
      end

      begin
        result = described_class.instrument("style_capsule.test.input", payload) do
          "result"
        end

        expect(payload[:input_size]).to eq(input.bytesize)
        expect(result).to eq("result")
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end

    it "does not override existing input_size" do
      payload = {input_size: 100, css_content: "small"}

      subscriber = ActiveSupport::Notifications.subscribe("style_capsule.test.existing_size") do |*args|
        # Event handler
      end

      begin
        described_class.instrument("style_capsule.test.existing_size", payload) do
          "result"
        end

        expect(payload[:input_size]).to eq(100)
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end
  end

  describe ".notify" do
    it "does nothing when ActiveSupport::Notifications is not available" do
      # Stub available? to return false
      allow(described_class).to receive(:available?).and_return(false)

      expect {
        described_class.notify("test.event", {test: "data"})
      }.not_to raise_error
    end

    it "does nothing when no subscribers exist" do
      # Use an event name that definitely has no subscribers
      expect {
        described_class.notify("style_capsule.test.no_subscribers_#{SecureRandom.hex}", {test: "data"})
      }.not_to raise_error
    end

    it "instruments event when subscribers exist" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("style_capsule.test.with_subscriber") do |*args|
        events << args
      end

      begin
        described_class.notify("style_capsule.test.with_subscriber", {test: "data"})
        expect(events).not_to be_empty
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end
  end

  describe ".instrument_css_processing" do
    let(:component_class) do
      Class.new do
        def self.name
          "TestComponent"
        end
      end
    end

    it "instruments CSS processing with correct payload" do
      css = ".test { color: red; }"
      result = described_class.instrument_css_processing(
        strategy: :selector_patching,
        component_class: component_class,
        capsule_id: "abc123",
        css_content: css
      ) do
        "processed css"
      end

      expect(result).to eq("processed css")
    end

    it "handles string component_class" do
      css = ".test { color: red; }"
      result = described_class.instrument_css_processing(
        strategy: :nesting,
        component_class: "StringComponent",
        capsule_id: "abc123",
        css_content: css
      ) do
        "processed css"
      end

      expect(result).to eq("processed css")
    end
  end

  describe ".instrument_file_write" do
    let(:component_class) do
      Class.new do
        def self.name
          "TestComponent"
        end
      end
    end

    it "instruments file write operations" do
      result = described_class.instrument_file_write(
        component_class: component_class,
        capsule_id: "abc123",
        file_path: "/tmp/test.css",
        size: 100
      ) do
        "write result"
      end

      expect(result).to eq("write result")
    end
  end

  describe ".instrument_fallback" do
    let(:component_class) do
      Class.new do
        def self.name
          "TestComponent"
        end
      end
    end

    it "instruments fallback events" do
      exception = StandardError.new("Permission denied")
      expect {
        described_class.instrument_fallback(
          component_class: component_class,
          capsule_id: "abc123",
          original_path: "/original/path",
          fallback_path: "/fallback/path",
          exception: [exception.class.name, exception.message],
          exception_object: exception
        )
      }.not_to raise_error
    end
  end

  describe ".instrument_fallback_failure" do
    let(:component_class) do
      Class.new do
        def self.name
          "TestComponent"
        end
      end
    end

    it "instruments fallback failure events" do
      original_exception = StandardError.new("Permission denied")
      fallback_exception = StandardError.new("Also failed")
      expect {
        described_class.instrument_fallback_failure(
          component_class: component_class,
          capsule_id: "abc123",
          original_path: "/original/path",
          fallback_path: "/fallback/path",
          original_exception: [original_exception.class.name, original_exception.message],
          original_exception_object: original_exception,
          fallback_exception: [fallback_exception.class.name, fallback_exception.message],
          fallback_exception_object: fallback_exception
        )
      }.not_to raise_error
    end
  end

  describe ".instrument_write_failure" do
    let(:component_class) do
      Class.new do
        def self.name
          "TestComponent"
        end
      end
    end

    it "instruments write failure events" do
      exception = StandardError.new("Write failed")
      expect {
        described_class.instrument_write_failure(
          component_class: component_class,
          capsule_id: "abc123",
          file_path: "/path/to/file",
          exception: [exception.class.name, exception.message],
          exception_object: exception
        )
      }.not_to raise_error
    end
  end

  describe ".instrument_registration" do
    it "instruments registration with file path" do
      result = described_class.instrument_registration(
        namespace: :default,
        file_path: "stylesheets/test",
        cache_strategy: :file
      ) do
        "registration result"
      end

      expect(result).to eq("registration result")
    end

    it "instruments registration with inline size" do
      result = described_class.instrument_registration(
        namespace: :admin,
        inline_size: 500,
        cache_strategy: :time
      ) do
        "registration result"
      end

      expect(result).to eq("registration result")
    end
  end
end
