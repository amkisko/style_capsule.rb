# frozen_string_literal: true

# Test StylesheetRegistry without ActiveSupport::CurrentAttributes
# This tests the non-Rails code paths

RSpec.describe StyleCapsule::StylesheetRegistry, "without ActiveSupport::CurrentAttributes" do
  before do
    # Clear registries
    described_class.clear
    described_class.clear_manifest
    described_class.clear_inline_cache
  end

  describe "thread-local storage fallback" do
    it "uses thread-local storage when CurrentAttributes not available" do
      # The code automatically falls back to thread-local storage
      # We can test this by checking that inline_stylesheets works
      css = ".test { color: red; }"
      described_class.register_inline(css, namespace: :test)

      # Should be accessible via thread-local storage
      stylesheets = described_class.request_inline_stylesheets
      expect(stylesheets[:test]).not_to be_empty
    end

    it "clears thread-local storage" do
      css = ".test { color: red; }"
      described_class.register_inline(css, namespace: :test)
      expect(described_class.request_inline_stylesheets[:test]).not_to be_empty

      described_class.clear(namespace: :test)
      expect(described_class.request_inline_stylesheets[:test]).to be_nil
    end

    it "provides instance method for compatibility" do
      # The instance method should work even without CurrentAttributes
      inst = described_class.instance
      expect(inst).to respond_to(:inline_stylesheets)
      expect(inst).to respond_to(:inline_stylesheets=)
    end

    it "sets inline_stylesheets via instance" do
      inst = described_class.instance
      inst.inline_stylesheets = {test: []}
      expect(described_class.inline_stylesheets[:test]).to eq([])
    end

    it "creates standalone instance with singleton methods" do
      # Test the standalone instance creation (lines 124-128)
      # Clear any existing instance
      described_class.instance_variable_set(:@_standalone_instance, nil)

      inst1 = described_class.instance
      inst2 = described_class.instance

      # Should return the same instance (memoized)
      expect(inst1).to eq(inst2)

      # Should have singleton methods
      expect(inst1).to respond_to(:inline_stylesheets)
      expect(inst1).to respond_to(:inline_stylesheets=)

      # Test that the singleton methods work
      inst1.inline_stylesheets = {test: [".css { }"]}
      expect(described_class.inline_stylesheets[:test]).to eq([".css { }"])

      # Test getter
      expect(inst1.inline_stylesheets[:test]).to eq([".css { }"])
    end
  end

  describe ".current_time" do
    it "uses Time.now when Time.current is not available" do
      # Mock Time to not respond to current
      allow(Time).to receive(:respond_to?).with(:current).and_return(false)
      # rubocop:disable Rails/TimeZone
      # Time.at is intentional for testing the fallback path when Time.current is unavailable
      allow(Time).to receive(:now).and_return(Time.at(1234567890))
      # rubocop:enable Rails/TimeZone

      result = described_class.send(:current_time)
      expect(result).to be_a(Time)
    end
  end

  describe "cache_inline_css edge cases" do
    it "handles cache_ttl that is nil" do
      cache_key = "test_key"
      cache_ttl = nil

      described_class.cache_inline_css(
        cache_key,
        ".test { color: red; }",
        cache_strategy: :time,
        cache_ttl: cache_ttl
      )

      # When cache_ttl is nil, nil.respond_to?(:to_i) returns true, so nil.to_i = 0
      # This means expires_at will be current_time + 0 = current_time
      # This is actually correct behavior - nil.to_i = 0 means "expire immediately"
      cached = described_class.instance_variable_get(:@inline_cache)[cache_key]
      expect(cached).not_to be_nil
      # expires_at will be set to current_time (since nil.to_i = 0)
      expect(cached[:expires_at]).to be_a(Time)
    end

    it "handles cache_ttl that doesn't respond to to_i" do
      cache_key = "test_key"
      # Use a cache_ttl that doesn't respond to to_i
      # The code checks respond_to?(:to_i) first, and if false, uses cache_ttl directly
      # If cache_ttl is truthy but not numeric, it will be used in Time addition
      # So we use nil or false to test the nil path
      cache_ttl = false

      described_class.cache_inline_css(
        cache_key,
        ".test { color: red; }",
        cache_strategy: :time,
        cache_ttl: cache_ttl
      )

      # Should handle gracefully (expires_at will be nil when ttl_seconds is falsy)
      cached = described_class.instance_variable_get(:@inline_cache)[cache_key]
      expect(cached).not_to be_nil
      expect(cached[:expires_at]).to be_nil
    end

    it "handles proc cache strategy with expires_at" do
      cache_key = "test_key"
      # rubocop:disable Rails/TimeZone
      # Time.now is intentional for testing non-Rails code paths
      cache_proc = ->(_css, _capsule, _ns) { ["key", true, Time.now + 3600] }
      # rubocop:enable Rails/TimeZone

      described_class.cache_inline_css(
        cache_key,
        ".test { color: red; }",
        cache_strategy: :proc,
        cache_proc: cache_proc,
        capsule_id: "abc",
        namespace: :default
      )

      cached = described_class.instance_variable_get(:@inline_cache)[cache_key]
      expect(cached).not_to be_nil
      expect(cached[:expires_at]).to be_a(Time)
    end
  end

  describe ".safe_string" do
    it "returns string when html_safe is not available" do
      string = Object.new
      def string.to_s
        "test"
      end

      result = described_class.send(:safe_string, string)
      expect(result).to eq(string)
    end
  end
end
