# frozen_string_literal: true

require "spec_helper"

RSpec.describe StyleCapsule do
  # Experimental Fiber isolation for request-scoped registry + helper cache.
  around do |example|
    previous = described_class.isolation_level
    example.run
  ensure
    described_class.isolation_level = previous
    StyleCapsule::StylesheetRegistry.clear
    StyleCapsule::ExecutionState.delete(StyleCapsule::ExecutionState::SCOPE_CACHE_KEY)
  end

  describe ".isolation_level" do
    it "defaults to :thread" do
      expect(described_class.isolation_level).to eq(:thread)
    end

    it "accepts :fiber" do
      described_class.isolation_level = :fiber
      expect(described_class.isolation_level).to eq(:fiber)
    end

    it "rejects unknown levels" do
      expect { described_class.isolation_level = :ractor }.to raise_error(ArgumentError, /:thread or :fiber/)
    end
  end

  describe "when isolation_level is :fiber" do
    before { described_class.isolation_level = :fiber }

    it "isolates inline stylesheets per Fiber", :aggregate_failures do
      seen = {}

      fiber_a = Fiber.new do
        StyleCapsule::StylesheetRegistry.register_inline(".a { color: red; }", namespace: :fiber_a)
        Fiber.yield
        seen[:a] = StyleCapsule::StylesheetRegistry.request_inline_stylesheets.keys
      end

      fiber_b = Fiber.new do
        StyleCapsule::StylesheetRegistry.register_inline(".b { color: blue; }", namespace: :fiber_b)
        Fiber.yield
        seen[:b] = StyleCapsule::StylesheetRegistry.request_inline_stylesheets.keys
      end

      fiber_a.resume
      fiber_b.resume
      fiber_a.resume
      fiber_b.resume

      expect(seen[:a]).to eq([:fiber_a])
      expect(seen[:b]).to eq([:fiber_b])
    end

    it "does not leak request file registrations across sibling Fibers" do
      leaked = nil

      Fiber.new do
        StyleCapsule::StylesheetRegistry.register("stylesheets/parent", namespace: :parent)
        Fiber.new do
          leaked = StyleCapsule::StylesheetRegistry.request_stylesheet_files
        end.resume
      end.resume

      expect(leaked).to eq({})
    end
  end

  describe "when isolation_level stays :thread" do
    before { described_class.isolation_level = :thread }

    it "shares request-scoped inline stylesheets across Fibers on the same Thread" do
      StyleCapsule::StylesheetRegistry.register_inline(".shared { color: green; }", namespace: :shared)

      seen = nil
      Fiber.new do
        seen = StyleCapsule::StylesheetRegistry.request_inline_stylesheets.keys
      end.resume

      expect(seen).to include(:shared)
    end
  end
end
