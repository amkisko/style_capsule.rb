# frozen_string_literal: true

RSpec.describe StyleCapsule::VERSION do
  it "is defined" do
    expect(defined?(StyleCapsule::VERSION)).to be_truthy
  end

  it "is a string" do
    expect(StyleCapsule::VERSION).to be_a(String)
  end

  it "follows semantic versioning format" do
    expect(StyleCapsule::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
