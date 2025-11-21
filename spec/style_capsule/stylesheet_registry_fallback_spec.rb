# frozen_string_literal: true

# Test fallback paths when ActiveSupport::CurrentAttributes is not available
# These tests stub the availability check to test the thread-local fallback paths

RSpec.describe StyleCapsule::StylesheetRegistry, "fallback paths" do
  before do
    # Clear registries
    described_class.clear
    described_class.clear_manifest
    described_class.clear_inline_cache
    # Clear thread-local storage
    Thread.current[:style_capsule_inline_stylesheets] = nil
  end

  after do
    # Don't call reset if it doesn't exist (when not using CurrentAttributes)
    # The spec_helper will handle this, but we need to clear thread-local storage
    Thread.current[:style_capsule_inline_stylesheets] = nil
  end

  describe "when ActiveSupport::CurrentAttributes is not available" do
    before do
      # Stub the check to return false to test fallback paths
      allow(described_class).to receive(:using_current_attributes?).and_return(false)
    end

    it "uses thread-local storage for inline_stylesheets getter" do
      # Set via thread-local storage
      Thread.current[:style_capsule_inline_stylesheets] = {test: [".css { }"]}

      # Should retrieve from thread-local storage
      result = described_class.inline_stylesheets
      expect(result[:test]).to eq([".css { }"])
    end

    it "uses thread-local storage for inline_stylesheets setter" do
      # Set via class method
      described_class.inline_stylesheets = {test: [".css { }"]}

      # Should be stored in thread-local storage
      expect(Thread.current[:style_capsule_inline_stylesheets][:test]).to eq([".css { }"])
    end

    it "creates standalone instance when CurrentAttributes not available" do
      # Clear any existing instance
      described_class.instance_variable_set(:@_standalone_instance, nil)

      inst = described_class.instance
      expect(inst).to be_a(Object)
      expect(inst).to respond_to(:inline_stylesheets)
      expect(inst).to respond_to(:inline_stylesheets=)

      # Test that singleton methods work
      inst.inline_stylesheets = {test: [".css { }"]}
      expect(described_class.inline_stylesheets[:test]).to eq([".css { }"])
    end

    it "registers inline CSS using thread-local storage" do
      css = ".test { color: red; }"
      described_class.register_inline(css, namespace: :test)

      # Should be accessible via thread-local storage
      stylesheets = described_class.request_inline_stylesheets
      expect(stylesheets[:test]).not_to be_empty
      # stylesheets[:test] is an array of hashes
      first_item = stylesheets[:test].first
      expect(first_item).to be_a(Hash)
      expect(first_item[:css_content]).to eq(css)
    end
  end
end
